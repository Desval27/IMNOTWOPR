/**
 * @file lightman_pico.h
 * @brief GPIO assignments for the original RP2040 Raspberry Pi Pico.
 *
 * All constants are GPIO numbers, not header pin numbers. VGA requires the
 * consecutive HSYNC, VSYNC, red, green and blue ordering on GPIO16 through GPIO20.
 */
#pragma once
// GPIO numbers, not Pico physical header positions.
namespace lightman::pins
{
constexpr unsigned tx = 0, rx = 1, cts = 2, rts = 3, dtr = 4, dsr = 5;
constexpr unsigned dcd = 6, ri = 7;
constexpr unsigned ps2_clock = 8, ps2_data = 9;
constexpr unsigned hsync = 16, vsync = 17, red = 18, green = 19, blue = 20;
} // namespace lightman::pins
