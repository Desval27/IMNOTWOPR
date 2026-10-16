/**
 * @file raster.h
 * @brief Pack 80/132-column glyph rows into the fixed 640-pixel VGA raster.
 */
#pragma once
#include <array>
#include <cstdint>

namespace lightman
{
constexpr int raster_width = 640, raster_bytes = raster_width / 8;

// Merge source pixels when narrowing to four or five pixels, so thin strokes
// (including DEC vertical rules) survive. Keep this out of the scanline loop.
inline constexpr auto narrow_glyphs = [] {
    std::array<std::array<uint8_t, 256>, 2> table{};
    for (int width = 4; width <= 5; ++width)
        for (int bits = 0; bits < 256; ++bits)
            for (int x = 0; x < 8; ++x)
                if (bits & (128 >> x))
                    table[width - 4][bits] |= 1u << (width - 1 - x * width / 8);
    return table;
}();

/**
 * @brief Narrow an eight-pixel glyph row to a cell's raster width.
 * @pre width is 4, 5 or 8. Result is right-aligned.
 */
inline uint8_t fit_glyph_row(uint8_t bits, int width)
{
    return width == 8 ? bits : narrow_glyphs[width - 4][bits];
}

/**
 * @brief OR a right-aligned glyph row into a cleared raster, including byte crossings.
 * @pre 0 <= left; left + width <= raster_width; width is 4, 5 or 8.
 */
inline void pack_glyph_row(uint8_t *dst, int left, int width, uint8_t bits)
{
    const int offset = left & 7;
    const uint16_t packed = uint16_t(bits) << (16 - offset - width);
    dst[left / 8] |= packed >> 8;
    if (offset + width > 8)
        dst[left / 8 + 1] |= packed & 255;
}
} // namespace lightman
