#include "joshua/i2c.hpp"
#include <algorithm>
#include <stdexcept>
#include <utility>

namespace joshua
{
I2cBus::I2cBus(std::vector<Byte> addresses) : addresses_(std::move(addresses))
{
    std::sort(addresses_.begin(), addresses_.end());
    for (auto address : addresses_)
        if (address < 0x08 || address > 0x77)
            throw std::runtime_error("i2c-target must be a 7-bit address in $08..$77");
    if (std::adjacent_find(addresses_.begin(), addresses_.end()) != addresses_.end())
        throw std::runtime_error("duplicate i2c-target address");
}

void I2cBus::reset(bool scl, bool sda)
{
    phase_ = Phase::idle;
    bits_ = byte_ = 0;
    pullSdaLow_ = false;
    scl_ = scl;
    sda_ = sda;
}

void I2cBus::update(bool scl, bool sda)
{
    if (!enabled())
        return;
    const bool resolvedSda = sda && !pullSdaLow_;
    if (scl_ && scl && resolvedSda != sda_)
    {
        // START (including repeated START) or STOP. Only changes while SCL
        // stays high qualify; a data change accompanying a falling clock does not.
        phase_ = resolvedSda ? Phase::idle : Phase::address;
        bits_ = byte_ = 0;
        pullSdaLow_ = false;
    }
    else if (!scl_ && scl && phase_ == Phase::address && bits_ < 8)
    {
        byte_ = static_cast<Byte>((byte_ << 1) | resolvedSda);
        ++bits_;
    }
    else if (scl_ && !scl)
    {
        if (phase_ == Phase::address && bits_ == 8)
        {
            // Assert after bit eight falls; hold through the ninth high period.
            // These targets only acknowledge write addresses, never payloads or reads.
            pullSdaLow_ = !(byte_ & 1) &&
                std::binary_search(addresses_.begin(), addresses_.end(), byte_ >> 1);
            phase_ = Phase::acknowledge;
        }
        else if (phase_ == Phase::acknowledge)
        {
            pullSdaLow_ = false;
            phase_ = Phase::ignore;
        }
    }
    scl_ = scl;
    // Remember our own SDA change without misinterpreting it as START/STOP.
    sda_ = sda && !pullSdaLow_;
}
}
