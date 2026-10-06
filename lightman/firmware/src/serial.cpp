/**
 * @file serial.cpp
 * @brief UART0 buffering and optional RS-232 flow control.
 *
 * The core 0 RX interrupt fills the receive ring. Foreground code owns the TX
 * queue and services it without blocking on CTS or received XOFF.
 */

#include "hardware.h"
#include "hardware/irq.h"
#include "hardware/sync.h"
#include "hardware/uart.h"
#include "lightman_pico.h"
#include "pico/stdlib.h"
#include <atomic>

namespace lightman
{
namespace
{

constexpr unsigned rx_size = 4096, tx_size = 1024;
uint8_t rx[rx_size], tx[tx_size];
std::atomic<unsigned> rh{0}, rt{0};
unsigned th = 0, tt = 0;
std::atomic<uint32_t> errors{0};
uint32_t drops = 0;
std::atomic<bool> stopped{false};
bool held = false, sent_xoff = false;
Config active;

/**
 * @brief Measure the receive-ring occupancy using published producer/consumer indices.
 * @return Number of queued bytes in the range 0..rx_size-1.
 */
unsigned rx_count()
{
    return (rh.load(std::memory_order_acquire) - rt.load(std::memory_order_acquire)) & (rx_size - 1);
}

/**
 * @brief Handle UART0 RX interrupts, errors and received software flow control.
 * @note Runs on core 0 in interrupt context; never blocks and is the sole RX-ring producer.
 */
void receive()
{
    while (uart_is_readable(uart0))
    {
        uint32_t raw = uart_get_hw(uart0)->dr;
        if (raw & 0xf00)
        {
            ++errors;
            uart_get_hw(uart0)->rsr = 0;
            continue;
        }

        uint8_t b = raw;
        if (active.flow == Flow::Software && (b == 0x11 || b == 0x13))
        {
            stopped.store(b == 0x13);
            continue;
        }

        auto h = rh.load(std::memory_order_relaxed), n = (h + 1) & (rx_size - 1);
        if (n == rt.load(std::memory_order_acquire))
            ++errors;
        else
        {
            rx[h] = b;
            rh.store(n, std::memory_order_release);
        }
    }

    if (active.flow == Flow::Hardware && rx_count() > rx_size * 3 / 4)
        gpio_put(pins::rts, 1);
}

/**
 * @brief Program UART framing/flow control and reset software flow-control state.
 * @param c Valid serial settings to install.
 * @pre UART0 is initialized and the RX interrupt cannot run concurrently.
 */
void configure(const Config &c)
{
    active = c;
    uart_set_baudrate(uart0, c.baud);
    uart_set_format(uart0, c.data_bits, c.stop_bits,
                    c.parity == 1   ? UART_PARITY_EVEN
                    : c.parity == 2 ? UART_PARITY_ODD
                                    : UART_PARITY_NONE);
    // CTS is hardware-gated; RTS follows the software RX ring, not just the FIFO.
    uart_set_hw_flow(uart0, c.flow == Flow::Hardware, false);
    stopped = false;
    sent_xoff = false;
    gpio_put(pins::rts, held && c.flow == Flow::Hardware);
}

} // namespace

/**
 * @brief Initialize UART0, handshake GPIOs and the core 0 RX interrupt.
 */
void serial_start(const Config &c)
{
    uart_init(uart0, c.baud);
    for (unsigned pin : {pins::tx, pins::rx, pins::cts})
        gpio_set_function(pin, GPIO_FUNC_UART);

    gpio_pull_up(pins::cts);

    for (unsigned pin : {pins::rts, pins::dtr})
    {
        gpio_init(pin);
        gpio_put(pin, 0);
        gpio_set_dir(pin, GPIO_OUT);
    }

    for (unsigned pin : {pins::dsr, pins::dcd, pins::ri})
    {
        gpio_init(pin);
        gpio_set_dir(pin, GPIO_IN);
        gpio_pull_up(pin);
    }

    configure(c);

    uart_set_fifo_enabled(uart0, true);
    irq_set_exclusive_handler(UART0_IRQ, receive);
    irq_set_enabled(UART0_IRQ, true);
    uart_set_irq_enables(uart0, true, false);
}

/**
 * @brief Check whether outgoing transmission has fully drained.
 */
bool serial_idle()
{
    return th == tt && !(uart_get_hw(uart0)->fr & UART_UARTFR_BUSY_BITS);
}

/**
 * @brief Apply UART settings only when queued transmission has finished.
 */
bool serial_apply(const Config &c)
{
    if (!serial_idle())
        return false;

    uint32_t irq = save_and_disable_interrupts();
    configure(c);
    restore_interrupts(irq);
    return true;
}

/**
 * @brief Request or release a local pause of the peer through configured flow control.
 */
void serial_hold(bool hold)
{
    held = hold;
}

/**
 * @brief Service RX backpressure and move queued TX bytes into the UART FIFO.
 */
void serial_poll()
{
    unsigned queued = rx_count();
    bool need_stop = held || queued > rx_size * 3 / 4;
    bool can_start = !held && queued < rx_size / 4;

    if (active.flow == Flow::Hardware)
    {
        uint32_t irq = save_and_disable_interrupts();
        if (held || rx_count() > rx_size * 3 / 4)
            gpio_put(pins::rts, 1);
        else if (rx_count() < rx_size / 4)
            gpio_put(pins::rts, 0);
        restore_interrupts(irq);
    }

    if (active.flow == Flow::Software && uart_is_writable(uart0))
    {
        if (need_stop && !sent_xoff)
        {
            uart_get_hw(uart0)->dr = 0x13;
            sent_xoff = true;
        }
        else if (can_start && sent_xoff)
        {
            uart_get_hw(uart0)->dr = 0x11;
            sent_xoff = false;
        }
    }

    while (tt != th && !stopped.load() && uart_is_writable(uart0))
    {
        uart_get_hw(uart0)->dr = tx[tt];
        tt = (tt + 1) % tx_size;
    }
}

/**
 * @brief Remove one received serial byte without blocking.
 */
int serial_read()
{
    auto t = rt.load(std::memory_order_relaxed);
    if (t == rh.load(std::memory_order_acquire))
        return -1;

    int b = rx[t];
    rt.store((t + 1) & (rx_size - 1), std::memory_order_release);
    return b;
}

/**
 * @brief Enqueue an entire outgoing byte sequence or discard it as a unit.
 */
void serial_write(std::string_view text)
{
    unsigned free = (tt + tx_size - th - 1) % tx_size;

    if (text.size() > free)
    {
        ++drops;
        return;
    }

    for (uint8_t c : text)
    {
        tx[th] = c;
        th = (th + 1) % tx_size;
    }
}

/**
 * @brief Read the accumulated serial receive error count.
 */
uint32_t serial_rx_errors()
{
    return errors.load();
}

/**
 * @brief Read the number of outgoing sequences rejected for lack of queue space.
 */
uint32_t serial_tx_drops()
{
    return drops;
}

/**
 * @brief Sample the active-low, transceiver-side DSR input.
 */
bool serial_dsr()
{
    return !gpio_get(pins::dsr);
}

/**
 * @brief Sample the active-low, transceiver-side DCD input.
 */
bool serial_dcd()
{
    return !gpio_get(pins::dcd);
}

/**
 * @brief Sample the active-low, transceiver-side RI input.
 */
bool serial_ri()
{
    return !gpio_get(pins::ri);
}

} // namespace lightman
