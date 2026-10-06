/**
 * @file ps2.cpp
 * @brief Interrupt-driven PS/2 input capture on GPIO6 and GPIO7.
 *
 * The core 0 GPIO interrupt produces validated bytes; the foreground loop consumes
 * them through a single-producer, single-consumer queue.
 */
#include "hardware.h"
#include "keyboard.h"
#include "lightman_pico.h"
#include "pico/stdlib.h"
#include <atomic>
namespace lightman
{
namespace
{
Ps2Frame frame;
uint8_t queue[128];
std::atomic<unsigned> head{0}, tail{0};
std::atomic<uint32_t> overflows{0};
/**
 * @brief Capture a PS/2 falling edge and enqueue a complete validated frame.
 * @param gpio GPIO that triggered the shared callback.
 * @param events GPIO interrupt event mask.
 * @note Runs on core 0 in interrupt context and discards bytes if the queue is full.
 */
void edge(unsigned gpio, uint32_t events)
{
    if (gpio != pins::ps2_clock || !(events & GPIO_IRQ_EDGE_FALL))
        return;
    int byte = frame.edge(gpio_get(pins::ps2_data), time_us_32());
    if (byte < 0)
        return;
    unsigned h = head.load(std::memory_order_relaxed), next = (h + 1) % 128;
    if (next == tail.load(std::memory_order_acquire))
    {
        ++overflows;
        return;
    }
    queue[h] = byte;
    head.store(next, std::memory_order_release);
}
} // namespace
/**
 * @brief Configure PS/2 input pull-ups and install the falling-clock-edge interrupt.
 */
void ps2_start()
{
    for (auto pin : {pins::ps2_clock, pins::ps2_data})
    {
        gpio_init(pin);
        gpio_set_dir(pin, GPIO_IN);
        gpio_pull_up(pin);
    }
    gpio_set_irq_enabled_with_callback(pins::ps2_clock, GPIO_IRQ_EDGE_FALL, true, edge);
}
/**
 * @brief Remove one validated PS/2 byte from the receive queue without blocking.
 */
int ps2_read()
{
    auto t = tail.load(std::memory_order_relaxed);
    if (t == head.load(std::memory_order_acquire))
        return -1;
    int result = queue[t];
    tail.store((t + 1) % 128, std::memory_order_release);
    return result;
}
/**
 * @brief Read the PS/2 receive-queue overflow count.
 */
uint32_t ps2_overflows()
{
    return overflows.load();
}
} // namespace lightman
