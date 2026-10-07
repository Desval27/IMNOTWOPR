/**
 * @file lightman_pico.h
 * @brief GPIO assignments for the original RP2040 Raspberry Pi Pico.
 *
 * All constants are GPIO numbers, not header pin numbers. VGA requires the
 * consecutive HSYNC, VSYNC, R0..R2, G0..G2, B0..B1 ordering on GPIO13 through GPIO22.
 * Channel 0 is the most significant DAC bit, as wired in the schematic.
 */
#pragma once
#include <cstdint>
// GPIO numbers, not Pico physical header positions.
namespace lightman::pins
{
constexpr unsigned tx = 0, rx = 1, cts = 2, rts = 3, dtr = 4, dsr = 5;
constexpr unsigned dcd = 6, ri = 7;
constexpr unsigned ps2_clock = 8, ps2_data = 9;
constexpr unsigned hsync = 13, vsync = 14;
constexpr unsigned red0 = 15, red1 = 16, red2 = 17;
constexpr unsigned green0 = 18, green1 = 19, green2 = 20;
constexpr unsigned blue0 = 21, blue1 = 22;
constexpr unsigned video_pin_count = 10;
constexpr uint32_t video_pin_mask = ((1u << video_pin_count) - 1) << hsync;
static_assert(vsync == hsync + 1 && red0 == hsync + 2 && red1 == hsync + 3 && red2 == hsync + 4 &&
              green0 == hsync + 5 && green1 == hsync + 6 && green2 == hsync + 7 && blue0 == hsync + 8 &&
              blue1 == hsync + 9);
} // namespace lightman::pins
