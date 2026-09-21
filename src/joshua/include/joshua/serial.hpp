#pragma once
#include <cstdint>
#include <string>
#include <string_view>

namespace joshua {
enum class Parity { none, even, odd, mark, space };

// Settings at the terminal end of the virtual serial connection.
// These are independent of the guest's ACIA command/control registers.
struct SerialSettings {
    std::uint32_t baud = 19200;
    unsigned dataBits = 8;
    Parity parity = Parity::none;
    unsigned stopHalfBits = 2; // 2, 3, 4 mean 1, 1.5, 2 stop bits.

    void validate() const;
    std::uint8_t dataMask() const;
    std::uint64_t frameCycles(std::uint32_t clockHz) const;
    std::string description() const;
};
Parity parseParity(std::string_view text);
unsigned parseStopBits(std::string_view text);
}
