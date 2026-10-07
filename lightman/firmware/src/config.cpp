/**
 * @file config.cpp
 * @brief Validation and little-endian serialization of terminal settings.
 *
 * Encodes versioned records with CRC32 independently of compiler structure padding.
 */

#include "config.h"
#include <algorithm>

namespace lightman
{

/**
 * @brief Check whether every field is supported by this firmware.
 */
bool Config::valid() const
{
    return std::find(baud_rates.begin(), baud_rates.end(), baud) != baud_rates.end() &&
           (data_bits == 7 || data_bits == 8) && (stop_bits == 1 || stop_bits == 2) && parity <= 2 &&
           static_cast<unsigned>(flow) <= 2 && font < 2 && vt52 <= 1 && echo <= 1 && backspace_del <= 1 &&
           color < normal_colors.size();
}

/**
 * @brief Compute reflected CRC32 with polynomial 0xEDB88320 and inverted endpoints.
 * @param p Readable input bytes.
 * @param n Number of bytes to include.
 * @return CRC32 covering exactly n bytes.
 */
static uint32_t crc(const uint8_t *p, size_t n)
{
    uint32_t c = ~0u;
    while (n--)
    {
        c ^= *p++;
        for (int i = 0; i < 8; ++i)
            c = (c >> 1) ^ ((0u - (c & 1)) & 0xedb88320u);
    }
    return ~c;
}

/**
 * @brief Store a 32-bit value as four little-endian bytes.
 * @param[out] p Writable buffer of at least four bytes.
 * @param v Value to encode.
 */
static void put32(uint8_t *p, uint32_t v)
{
    for (int i = 0; i < 4; ++i)
        p[i] = v >> (8 * i);
}

/**
 * @brief Read a 32-bit value from four little-endian bytes.
 * @param p Readable buffer of at least four bytes.
 * @return Decoded unsigned value.
 */
static uint32_t get32(const uint8_t *p)
{
    uint32_t v = 0;
    for (int i = 0; i < 4; ++i)
        v |= uint32_t(p[i]) << (8 * i);
    return v;
}

/**
 * @brief Serialize settings into a versioned little-endian record with CRC32.
 */
std::array<uint8_t, settings_size> encode_config(const Config &c, uint32_t generation)
{
    std::array<uint8_t, settings_size> b{};
    put32(b.data(), 0x314d544c);
    put32(b.data() + 4, generation);
    put32(b.data() + 8, c.baud);
    b[12] = c.data_bits;
    b[13] = c.stop_bits;
    b[14] = c.parity;
    b[15] = static_cast<uint8_t>(c.flow);
    b[16] = c.font;
    b[17] = c.vt52;
    b[18] = c.echo;
    b[19] = c.backspace_del;
    b[20] = c.color;
    put32(b.data() + 28, crc(b.data(), 28));
    return b;
}

/**
 * @brief Validate a settings record and decode it without partial output updates.
 */
bool decode_config(const uint8_t *b, Config &c, uint32_t &generation)
{
    if (get32(b) != 0x314d544c || get32(b + 28) != crc(b, 28))
        return false;
    Config candidate;
    candidate.baud = get32(b + 8);
    candidate.data_bits = b[12];
    candidate.stop_bits = b[13];
    candidate.parity = b[14];
    candidate.flow = static_cast<Flow>(b[15]);
    candidate.font = b[16];
    candidate.vt52 = b[17];
    candidate.echo = b[18];
    candidate.backspace_del = b[19];
    candidate.color = b[20];
    if (!candidate.valid())
        return false;
    c = candidate;
    generation = get32(b + 4);
    return true;
}
} // namespace lightman
