/**
 * @file hardware.h
 * @brief Core 0 interfaces to VGA, PS/2, serial I/O and settings storage.
 *
 * Initialize each driver before use. Unless noted otherwise, call these functions
 * from the core 0 foreground loop, not interrupt handlers or core 1.
 */
#pragma once
#include "config.h"
#include "terminal.h"
namespace lightman
{
/**
 * @brief Initialize VGA rendering, claim PIO/DMA resources and launch core 1.
 * @pre Call once on core 0 after setting the system clock to 126 MHz.
 * @note Uses GPIO16..20, one PIO0 state machine and two DMA channels.
 */
void video_start();
/**
 * @brief Render and publish a complete frame without modifying the scanned buffer.
 * @param t Terminal cells and cursor state to render; must remain stable during this call.
 * @param c Valid configuration selecting the base font and text color.
 * @pre video_start() has completed.
 * @note Core 1 adopts the latest published frame at a frame boundary.
 */
void video_publish(const Terminal &t, const Config &c);
/**
 * @brief Stop VGA DMA and wait for core 1 to park in SRAM with interrupts disabled.
 * @pre Video is running and no pause is already outstanding.
 * @note Blocks on core 0; pair with video_resume() after flash access completes.
 */
void video_pause();
/**
 * @brief Release core 1 from its park loop and wait for its acknowledgement.
 * @pre video_pause() has completed and flash/XIP is available again.
 */
void video_resume();
/**
 * @brief Read the accumulated scanline deadline-miss count.
 * @return Number of detected occasions when the next DMA channel was already idle.
 */
uint32_t video_underruns();
/**
 * @brief Configure PS/2 input pull-ups and install the falling-clock-edge interrupt.
 * @pre Call once on core 0 with suitable external level shifting in place.
 * @note The driver receives default scan-code set 2 and sends no keyboard commands.
 */
void ps2_start();
/**
 * @brief Remove one validated PS/2 byte from the receive queue without blocking.
 * @return Byte in 0..255, or -1 when the queue is empty.
 */
int ps2_read();
/**
 * @brief Read the PS/2 receive-queue overflow count.
 * @return Number of valid bytes discarded because the queue was full.
 */
uint32_t ps2_overflows();
/**
 * @brief Initialize UART0, handshake GPIOs and the core 0 RX interrupt.
 * @param c Valid initial baud, framing and flow-control settings.
 * @pre Call once on core 0.
 * @note Asserts DTR and leaves TX queue servicing to serial_poll().
 */
void serial_start(const Config &c);
/**
 * @brief Apply UART settings only when queued transmission has finished.
 * @param c Valid replacement serial settings.
 * @return True if applied; false if queued bytes or an active UART transmission remain.
 * @pre Release old flow control and pause the peer before changing framing.
 * @note Does not clear the RX ring or persist settings.
 */
bool serial_apply(const Config &c);
/**
 * @brief Service RX backpressure and move queued TX bytes into the UART FIFO.
 * @note Call frequently on core 0. Never waits for CTS or XON; local software
 * flow-control bytes bypass the ordinary TX queue and received XOFF.
 */
void serial_poll();
/**
 * @brief Remove one received serial byte without blocking.
 * @return Byte in 0..255, or -1 when no data is queued.
 * @note With software flow control enabled, received XON/XOFF is consumed by the driver.
 */
int serial_read();
/**
 * @brief Enqueue an entire outgoing byte sequence or discard it as a unit.
 * @param text Bytes to copy into the bounded TX ring; embedded NUL is supported.
 * @note Insufficient space increments serial_tx_drops(). Transmission requires serial_poll().
 */
void serial_write(std::string_view text);
/**
 * @brief Request or release a local pause of the peer through configured flow control.
 * @param hold True to request a pause; false to allow normal RX watermark handling.
 * @note Takes effect through serial_poll(); does not stop receiving or affect Flow::None.
 */
void serial_hold(bool hold);
/**
 * @brief Check whether outgoing transmission has fully drained.
 * @return True when the software TX queue is empty and UART0 is no longer busy.
 */
bool serial_idle();
/**
 * @brief Read the accumulated serial receive error count.
 * @return Count of UART error observations plus bytes discarded on RX-ring overflow.
 */
uint32_t serial_rx_errors();
/**
 * @brief Read the number of outgoing sequences rejected for lack of queue space.
 * @return Rejected sequence count, not the number of discarded bytes.
 */
uint32_t serial_tx_drops();
/**
 * @brief Sample the active-low, transceiver-side DSR input.
 * @return True when DSR is asserted; DSR does not gate transmission.
 */
bool serial_dsr();
/**
 * @brief Select and decode the newest valid flash settings record.
 * @return Saved configuration, or factory defaults when neither slot is valid.
 * @pre Call once on core 0 during startup, before the first settings_save().
 */
Config settings_load();
/**
 * @brief Save validated settings to the alternate flash sector and verify the write.
 * @param config Configuration to persist.
 * @return True on verified success; false for invalid settings or a verification failure.
 * @pre settings_load() and video_start() have completed; the peer is paused.
 * @note Temporarily stops video and disables interrupts during flash operations.
 * The previous slot remains intact. This does not apply settings to the running drivers.
 */
bool settings_save(const Config &config);
} // namespace lightman
