/**
 * @file colors.h
 * @brief Normal-text presets and RGB332 conversion for the prototype resistor DACs.
 */

#pragma once
#include <array>
#include <cstdint>

namespace lightman
{

struct ColorPreset
{
    const char *name;
    uint8_t rgb332; // RRR GGG BB, most significant channel bits first.
};

// Keep the original white/green/yellow indices compatible with saved settings.
inline constexpr std::array<ColorPreset, 8> normal_colors = {{{"White", 0xff},
                                                              {"Classic green", 0x1c},
                                                              {"Yellow", 0xfc},
                                                              {"Amber", 0xf0},
                                                              {"Red", 0xe0},
                                                              {"Blue", 0x03},
                                                              {"Cyan", 0x1f},
                                                              {"Magenta", 0xe3}}};
inline constexpr uint8_t default_normal_color = 0;

/**
 * @brief Encode RGB332 as HS, VS, R0..R2, G0..G2, B0..B1 in a DMA halfword.
 * @note In this schematic, channel 0 has the smallest resistor (greatest weight).
 * Both negative-polarity sync signals are inactive for visible pixels.
 */
constexpr uint16_t vga_pixel(uint8_t rgb332)
{
    uint16_t result = 3;
    for (unsigned bit = 0; bit < 8; ++bit)
        result |= ((rgb332 >> (7 - bit)) & 1u) << (bit + 2);
    return result;
}

} // namespace lightman
