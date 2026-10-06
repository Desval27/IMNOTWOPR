/**
 * @file video.cpp
 * @brief PIO/DMA VGA scanout with three packed raster buffers.
 *
 * Core 0 renders complete frames; core 1 expands scanlines and rearms DMA.
 * A short spinlock protects buffer ownership. Scanout uses 800 by 525 total
 * pixels at 25.2 MHz, with an 80 by 24 text image centered in the visible area.
 */
#include "fonts.h"
#include "hardware.h"
#include "hardware/dma.h"
#include "hardware/pio.h"
#include "lightman_pico.h"
#include "pico/multicore.h"
#include "pico/stdlib.h"
#include "video.pio.h"
#include <atomic>
#include <cstring>

namespace lightman
{
namespace
{
constexpr int width = 800, height = 525, raster_height = rows * 16;
// Three packed 1bpp rasters: scanning, published, and being drawn. Core0 never
// writes the raster core1 is scanning. Only indices change under the spinlock.
/**
 * @brief Packed 1-bit raster and color selection exchanged between the two cores.
 */
struct Frame
{
    uint8_t bits[raster_height][columns];
    uint8_t color = 0;
};
Frame frames[3]{};
int scanning = 0, published = 0;
spin_lock_t *frame_lock;
std::atomic<bool> pause_request{false}, paused{false};
std::atomic<uint32_t> underruns{0};
alignas(4) uint32_t lines[2][width / 4];
uint32_t pixels[3][256][2];
uint8_t glyphs[2][128][16];
uint8_t graphics[32][16];
int channels[2];
PIO pio = pio0;
unsigned sm, program_offset;
/**
 * @brief Build DEC drawing glyphs and ASCII approximations in SRAM.
 * @pre The base glyph tables have been copied into glyphs.
 */
void make_graphics()
{
    for (int c = 0; c < 32; ++c)
        std::memcpy(graphics[c], glyphs[0]['?'], 16);
    auto line = [](char c, bool up, bool down, bool left, bool right) {
        auto *g = graphics[c - '_'];
        std::memset(g, 0, 16);
        for (int y = 0; y < 16; ++y)
        {
            if ((up && y <= 7) || (down && y >= 7))
                g[y] |= 0x10;
            if (y == 7)
            {
                if (left)
                    g[y] |= 0xf0;
                if (right)
                    g[y] |= 0x1f;
            }
        }
    };
    line('j', true, false, true, false);
    line('k', false, true, true, false);
    line('l', false, true, false, true);
    line('m', true, false, false, true);
    line('n', true, true, true, true);
    line('q', false, false, true, true);
    line('t', true, true, false, true);
    line('u', true, true, true, false);
    line('v', true, false, true, true);
    line('w', false, true, true, true);
    line('x', true, true, false, false);
    for (char c : {'o', 'p', 'r', 's'})
    {
        auto *g = graphics[c - '_'];
        std::memset(g, 0, 16);
        g[c == 'o' ? 1 : c == 'p' ? 4 : c == 'r' ? 10 : 13] = 255;
    }
    std::memset(graphics[0], 0, 16);
    constexpr uint8_t diamond[16] = {0, 0, 0, 0, 0x10, 0x38, 0x7c, 0xfe, 0x7c, 0x38, 0x10, 0, 0, 0, 0, 0};
    std::memcpy(graphics['`' - '_'], diamond, 16);
    for (int y = 0; y < 16; ++y)
        graphics['a' - '_'][y] = (y & 1) ? 0x55 : 0xaa;
    const char replacements[][2] = {{'b', 'H'}, {'c', 'F'}, {'d', 'R'}, {'e', 'L'}, {'h', 'N'}, {'i', 'V'}, {'y', '<'},
                                    {'z', '>'}, {'{', 'p'}, {'|', '!'}, {'}', 'L'}, {'~', '.'}, {'f', 'o'}, {'g', '+'}};
    for (auto &pair : replacements)
        std::memcpy(graphics[pair[0] - '_'], glyphs[0][int(pair[1])], 16);
}
/**
 * @brief Expand one VGA scanline, including sync pulses and blanking, into DMA bytes.
 * @param[out] dst Word-aligned destination with space for width bytes.
 * @param y Physical scanline index in 0..height-1.
 * @param frame Index of the immutable raster currently owned by scanout.
 * @note Runs on core 1 from SRAM; one lookup expands eight visible pixels.
 */
void __not_in_flash_func(render)(uint32_t *dst, int y, int frame)
{
    const uint8_t sync = y >= 490 && y < 492 ? 1 : 3;
    std::memset(dst, sync, width);
    std::memset(reinterpret_cast<uint8_t *>(dst) + 656, sync & ~1, 96);
    if (y < 48 || y >= 432)
        return;
    const auto *src = frames[frame].bits[y - 48];
    const auto *lookup = pixels[frames[frame].color];
    for (int x = 0; x < columns; ++x)
    {
        dst[2 * x] = lookup[src[x]][0];
        dst[2 * x + 1] = lookup[src[x]][1];
    }
}
/**
 * @brief Adopt the newest published raster if the ownership lock is immediately available.
 * @return Raster index that remains owned by core 1 for the next frame.
 * @note Called only by core 1 at frame boundaries; retains the old raster on contention.
 */
int snapshot()
{
    uint32_t irq = save_and_disable_interrupts();
    if (spin_try_lock_unsafe(frame_lock))
    {
        scanning = published;
        spin_unlock(frame_lock, irq);
    }
    else
        restore_interrupts(irq);
    return scanning;
}
/**
 * @brief Run the scanline/DMA loop and service core 0 pause requests.
 * @note Never returns. During flash saves, parks in SRAM with interrupts disabled.
 */
void __not_in_flash_func(core1)()
{
    while (true)
    {
        int frame = snapshot();
        render(lines[0], 0, frame);
        render(lines[1], 1, frame);
        for (int i = 0; i < 2; ++i)
        {
            dma_channel_set_read_addr(channels[i], lines[i], false);
            dma_channel_set_trans_count(channels[i], width, false);
        }
        pio_sm_clear_fifos(pio, sm);
        pio_sm_restart(pio, sm);
        pio_sm_exec(pio, sm, pio_encode_jmp(program_offset));
        dma_start_channel_mask(1u << channels[0]);
        pio_sm_set_enabled(pio, sm, true);
        int next = 2, completed = 0;
        while (!pause_request.load(std::memory_order_acquire))
        {
            int ch = channels[completed];
            while (dma_channel_is_busy(ch))
                tight_loop_contents();
            if (!dma_channel_is_busy(channels[completed ^ 1]))
                ++underruns;
            if (next == 0)
                frame = snapshot();
            render(lines[completed], next, frame);
            dma_channel_set_read_addr(ch, lines[completed], false);
            dma_channel_set_trans_count(ch, width, false);
            if (!dma_channel_is_busy(channels[completed ^ 1]) && !dma_channel_is_busy(ch))
                dma_start_channel_mask(1u << ch);
            completed ^= 1;
            next = (next + 1) % height;
        }
        pio_sm_set_enabled(pio, sm, false);
        for (int ch : channels)
            dma_channel_abort(ch);
        pio_sm_set_pins_with_mask(pio, sm, 3u << pins::hsync, 31u << pins::hsync);
        uint32_t irq = save_and_disable_interrupts();
        paused.store(true, std::memory_order_release);
        while (pause_request.load(std::memory_order_acquire))
            __asm volatile("nop");
        restore_interrupts(irq);
        paused.store(false, std::memory_order_release);
    }
}
} // namespace
/**
 * @brief Initialize VGA rendering, claim PIO/DMA resources and launch core 1.
 */
void video_start()
{
    frame_lock = spin_lock_init(spin_lock_claim_unused(true));
    std::memcpy(glyphs, font_data, sizeof glyphs);
    make_graphics();
    const uint8_t colors[] = {28, 8, 12};
    for (int color = 0; color < 3; ++color)
        for (int b = 0; b < 256; ++b)
        {
            uint8_t packed[8];
            for (int x = 0; x < 8; ++x)
                packed[x] = 3 + ((b & (128 >> x)) ? colors[color] : 0);
            std::memcpy(pixels[color][b], packed, 8);
        }
    sm = pio_claim_unused_sm(pio, true);
    program_offset = pio_add_program(pio, &lightman_video_program);
    auto cfg = lightman_video_program_get_default_config(program_offset);
    sm_config_set_out_pins(&cfg, pins::hsync, 5);
    sm_config_set_out_shift(&cfg, true, true, 8);
    sm_config_set_fifo_join(&cfg, PIO_FIFO_JOIN_TX);
    sm_config_set_clkdiv(&cfg, 1.0f);
    for (unsigned pin = pins::hsync; pin <= pins::blue; ++pin)
        pio_gpio_init(pio, pin);
    pio_sm_set_consecutive_pindirs(pio, sm, pins::hsync, 5, true);
    pio_sm_init(pio, sm, program_offset, &cfg);
    for (int &ch : channels)
        ch = dma_claim_unused_channel(true);
    for (int i = 0; i < 2; ++i)
    {
        auto dc = dma_channel_get_default_config(channels[i]);
        channel_config_set_transfer_data_size(&dc, DMA_SIZE_8);
        channel_config_set_read_increment(&dc, true);
        channel_config_set_write_increment(&dc, false);
        channel_config_set_dreq(&dc, pio_get_dreq(pio, sm, true));
        channel_config_set_chain_to(&dc, channels[i ^ 1]);
        channel_config_set_high_priority(&dc, true);
        dma_channel_configure(channels[i], &dc, &pio->txf[sm], lines[i], width, false);
    }
    multicore_launch_core1(core1);
}
/**
 * @brief Render and publish a complete frame without modifying the scanned buffer.
 */
void video_publish(const Terminal &t, const Config &c)
{
    auto irq = spin_lock_blocking(frame_lock);
    int back = 0;
    while (back == scanning || back == published)
        ++back;
    spin_unlock(frame_lock, irq);
    auto &frame = frames[back];
    frame.color = c.color;
    bool blink = (time_us_64() / 500000) % 2 == 0;
    for (int row = 0; row < rows; ++row)
        for (int x = 0; x < columns; ++x)
        {
            Cell cell = t.cells()[row * columns + x];
            const auto *glyph = (cell.attr & Graphics) && cell.ch >= '_' && cell.ch <= '~'
                                    ? graphics[cell.ch - '_']
                                    : glyphs[(cell.attr & Bold) ? 1 : c.font][cell.ch & 127];
            for (int gy = 0; gy < 16; ++gy)
            {
                uint8_t bits = glyph[gy];
                if ((cell.attr & Underline) && gy == 14)
                    bits = 255;
                if ((cell.attr & Blink) && !blink)
                    bits = 0;
                if (bool(cell.attr & Reverse) ^ t.reverse_screen())
                    bits = ~bits;
                if (t.cursor_visible() && blink && t.x() == x && t.y() == row && gy >= 14)
                    bits = ~bits;
                frame.bits[row * 16 + gy][x] = bits;
            }
        }
    irq = spin_lock_blocking(frame_lock);
    published = back;
    spin_unlock(frame_lock, irq);
}
/**
 * @brief Stop VGA DMA and wait for core 1 to park in SRAM with interrupts disabled.
 */
void video_pause()
{
    pause_request.store(true, std::memory_order_release);
    while (!paused.load(std::memory_order_acquire))
        tight_loop_contents();
}
/**
 * @brief Release core 1 from its park loop and wait for its acknowledgement.
 */
void video_resume()
{
    pause_request.store(false, std::memory_order_release);
    while (paused.load(std::memory_order_acquire))
        tight_loop_contents();
}
/**
 * @brief Read the accumulated scanline deadline-miss count.
 */
uint32_t video_underruns()
{
    return underruns.load();
}
} // namespace lightman
