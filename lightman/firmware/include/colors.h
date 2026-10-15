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
inline constexpr std::array<ColorPreset, 8> normal_colors = {
    {
		{"Alice Blue", 0xFF},
		{"Antique White", 0xFF},
		{"Aqua", 0x1F},
		{"Aquamarine", 0x7F},
		{"Azure", 0xFF},
		{"Beige", 0xFF},
		{"Bisque", 0xFF},
		{"Black", 0x00},
		{"Blanched Almond", 0xFF},
		{"Blue", 0x03},
		{"Blue Violet", 0x87},
		{"Brown", 0xA4},
		{"Burly Wood", 0xD6},
		{"Cadet Blue", 0x52},
		{"Chartreuse", 0x7C},
		{"Chocolate", 0xCC},
		{"Coral", 0xED},
		{"Cornflower Blue", 0x73},
		{"Cornsilk", 0xFF},
		{"Crimson", 0xC0},
		{"Cyan", 0x1F},
		{"Dark Blue", 0x02},
		{"Dark Cyan", 0x12},
		{"Dark Goldenrod", 0xB0},
		{"Dark Gray", 0xB6},
		{"Dark Green", 0x0C},
		{"Dark Khaki", 0xB5},
		{"Dark Magenta", 0x82},
		{"Dark Olive Green", 0x4C},
		{"Dark Orange", 0xF0},
		{"Dark Orchid", 0x87},
		{"Dark Red", 0x80},
		{"Dark Salmon", 0xF1},
		{"Dark Sea Green", 0x96},
		{"Dark Slate Blue", 0x46},
		{"Dark Slate Gray", 0x29},
		{"Dark Turquoise", 0x1B},
		{"Dark Violet", 0x83},
		{"Deep Pink", 0xE2},
		{"Deep Sky Blue", 0x17},
		{"Dim Gray", 0x6D},
		{"Dodger Blue", 0x13},
		{"Fire Brick", 0xA4},
		{"Floral White", 0xFF},
		{"Forest Green", 0x30},
		{"Fuchsia", 0xE3},
		{"Gainsboro", 0xDB},
		{"Ghost White", 0xFF},
		{"Gold", 0xF8},
		{"Goldenrod", 0xD4},
		{"Gray", 0x92},
		{"Green", 0x10},
		{"Green Yellow", 0xBC},
		{"Honeydew", 0xFF},
		{"Hot Pink", 0xEE},
		{"Indian Red", 0x1B},
		{"Indigo", 0x42},
		{"Ivory", 0xFF},
		{"Khaki", 0xFE},
		{"Lavender", 0xFF},
		{"Lavender Blush", 0xFF},
		{"Lawn Green", 0x7C},
		{"Lemon Chiffon", 0xFF},
		{"Light Blue", 0xBB},
		{"Light Coral", 0xF2},
		{"Light Cyan", 0xFF},
		{"Light Goldenrod Yellow", 0xFF},
		{"Light Gray", 0xDB},
		{"Light Green", 0x9E},
		{"Light Pink", 0xF7},
		{"Light Salmon", 0xF5},
		{"Light Sea Green", 0x36},
		{"Light Sky Blue", 0x9B},
		{"Light Slate Gray", 0x72},
		{"Light Steel Blue", 0xBB},
		{"Light Yellow", 0xFF},
		{"Lime", 0x1C},
		{"Lime Green", 0x38},
		{"Linen", 0xFF},
		{"Magenta", 0xE3},
		{"Maroon", 0x80},
		{"Medium Aquamarine", 0x7A},
		{"Medium Blue", 0x03},
		{"Medium Orchid", 0xAB},
		{"Medium Purple", 0x8F},
		{"Medium Sea Green", 0x35},
		{"Medium Slate Blue", 0x6F},
		{"Medium Spring Green", 0x1E},
		{"Medium Turquoise", 0x5B},
		{"Medium Violet Red", 0xC2},
		{"Midnight Blue", 0x01},
		{"Mint Cream", 0xFF},
		{"Misty Rose", 0xFF},
		{"Moccasin", 0xFE},
		{"Navajo White", 0xFA},
		{"Navy", 0x02},
		{"Old Lace", 0xFF},
		{"Olive", 0x90},
		{"Olive Drab", 0x70},
		{"Orange", 0xF4},
		{"Orange Red", 0xE8},
		{"Orchid", 0xCF},
		{"Pale Goldenrod", 0xFE},
		{"Pale Green", 0x9E},
		{"Pale Turquoise", 0xBF},
		{"Pale Violet Red", 0xCE},
		{"Papaya Whip", 0xFF},
		{"Peach Puff", 0xFA},
		{"Peru", 0xD0},
		{"Pink", 0xFB},
		{"Plum", 0xD7},
		{"Powder Blue", 0xBF},
		{"Purple", 0x82},
		{"Red", 0xE0},
		{"Rosy Brown", 0xB2},
		{"Royal Blue", 0x4F},
		{"Saddle Brown", 0x88},
		{"Salmon", 0xF1},
		{"Sandy Brown", 0xF5},
		{"Sea Green", 0x31},
		{"Sea Shell", 0xFF},
		{"Sienna", 0xA8},
		{"Silver", 0xDB},
		{"Sky Blue", 0x9B},
		{"Slate Blue", 0x6B},
		{"Slate Gray", 0x72},
		{"Snow", 0xFF},
		{"Spring Green", 0x1D},
		{"Steel Blue", 0x52},
		{"Tan", 0xD6},
		{"Teal", 0x12},
		{"Thistle", 0xD7},
		{"Tomato", 0xED},
		{"Turquoise", 0x5F},
		{"Violet", 0xF3},
		{"Wheat", 0xFA},
		{"White", 0xFF},
		{"White Smoke", 0xFF},
		{"Yellow", 0xFC},
		{"Yellow Green", 0x98},
        // {"White", 0xff},
        // {"Classic green", 0x1c},
        // {"Yellow", 0xfc},
        // {"Amber", 0xf0},
        // {"Red", 0xe0},
        // {"Blue", 0x03},
        // {"Cyan", 0x1f},
        // {"Magenta", 0xe3},
        // {"Gray", 0x92},
        // {"Orange", 0xf8},
        // {"Pink", 0xe7},
        // {"Purple", 0x83},
        // {"Teal", 0x1b},
        // {"Brown", 0x84},
        // {"Light gray", 0xd6},
        // {"Dark gray", 0x49},
    }   
};

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
