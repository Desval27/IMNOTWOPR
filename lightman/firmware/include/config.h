/**
 * @file config.h
 * @brief Terminal configuration and portable flash-record serialization.
 *
 * Defines supported settings and the fixed-size, versioned CRC32 record format.
 */
#pragma once
#include <array>
#include <cstddef>
#include <cstdint>
namespace lightman
{
/**
 * @brief Serial flow-control policy selected in setup.
 */
enum class Flow : uint8_t
{
    None,
    Software,
    Hardware
};
/**
 * @brief User settings with factory defaults and bounded numeric choices.
 *
 * Parity values are 0/1/2 for none/even/odd; font values are 0/1 for regular/bold.
 * Color values are 0/1/2 for white/green/yellow. Boolean options use 0 or 1.
 */
struct Config
{
    uint32_t baud = 9600;
    uint8_t data_bits = 8, stop_bits = 1, parity = 0; // none, even, odd
    Flow flow = Flow::None;
    uint8_t font = 0, vt52 = 0, echo = 0, backspace_del = 1, color = 0;
    /**
     * @brief Check whether every field is supported by this firmware.
     * @return True when baud, framing, modes, font and color are in range.
     */
    bool valid() const;
};
constexpr std::array<uint32_t, 10> baud_rates = {300, 600, 1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200};
constexpr size_t settings_size = 32;
/**
 * @brief Serialize settings into a versioned little-endian record with CRC32.
 * @param c Settings to encode; this function does not validate their values.
 * @param generation Sequence number used to choose the newest valid flash slot.
 * @return Exactly settings_size bytes, including the record marker and checksum.
 */
std::array<uint8_t, settings_size> encode_config(const Config &c, uint32_t generation);
/**
 * @brief Validate a settings record and decode it without partial output updates.
 * @param b Readable buffer containing at least settings_size bytes.
 * @param[out] c Receives validated settings only on success.
 * @param[out] generation Receives the record sequence number only on success.
 * @return True if the marker, checksum and all setting values are valid.
 */
bool decode_config(const uint8_t *b, Config &c, uint32_t &generation);
} // namespace lightman
