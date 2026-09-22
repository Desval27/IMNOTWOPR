#include "joshua/serial.hpp"
#include <algorithm>
#include <cctype>
#include <stdexcept>

namespace joshua
{
    namespace
    {
        std::string parityName(Parity parity)
        {
            switch (parity)
            {
            case Parity::none:
                return "none";
            case Parity::even:
                return "even";
            case Parity::odd:
                return "odd";
            case Parity::mark:
                return "mark";
            case Parity::space:
                return "space";
            }
            throw std::runtime_error("invalid serial parity");
        }
    }
    void SerialSettings::validate() const
    {
        if (baud == 0 || baud > 4'000'000)
            throw std::runtime_error("serial baud must be 1..4000000");
        if (dataBits < 5 || dataBits > 8)
            throw std::runtime_error("serial data bits must be 5..8");
        if (stopHalfBits < 2 || stopHalfBits > 4)
            throw std::runtime_error("serial stop bits must be 1, 1.5 or 2");
        if (stopHalfBits == 3 && dataBits != 5)
            throw std::runtime_error("1.5 stop bits requires 5 data bits");
        parityName(parity);
    }
    std::uint8_t SerialSettings::dataMask() const
    {
        return static_cast<std::uint8_t>((1u << dataBits) - 1);
    }
    std::uint64_t SerialSettings::frameCycles(std::uint32_t clockHz) const
    {
        auto halfBits = 2 * (1 + dataBits + (parity != Parity::none)) + stopHalfBits;
        auto numerator = static_cast<std::uint64_t>(clockHz) * halfBits;
        auto denominator = static_cast<std::uint64_t>(baud) * 2;
        return std::max<std::uint64_t>(1, (numerator + denominator - 1) / denominator);
    }
    std::string SerialSettings::description() const
    {
        return std::to_string(baud) + " baud, " + std::to_string(dataBits) + " data bits, parity=" +
               parityName(parity) + ", " + (stopHalfBits == 3 ? "1.5" : std::to_string(stopHalfBits / 2)) +
               (stopHalfBits == 2 ? " stop bit" : " stop bits");
    }
    Parity parseParity(std::string_view text)
    {
        std::string value(text);
        std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c)
                       { return std::tolower(c); });
        if (value == "none" || value == "n")
            return Parity::none;
        if (value == "even" || value == "e")
            return Parity::even;
        if (value == "odd" || value == "o")
            return Parity::odd;
        if (value == "mark" || value == "m")
            return Parity::mark;
        if (value == "space" || value == "s")
            return Parity::space;
        throw std::runtime_error("serial parity must be none, even, odd, mark or space");
    }
    unsigned parseStopBits(std::string_view text)
    {
        if (text == "1")
            return 2;
        if (text == "1.5")
            return 3;
        if (text == "2")
            return 4;
        throw std::runtime_error("serial stop bits must be 1, 1.5 or 2");
    }
}
