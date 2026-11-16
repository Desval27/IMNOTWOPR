#pragma once
#include "joshua/memory.hpp"

namespace joshua
{
    // Single-controller, digital bus with address-only targets. No host callbacks
    // or pointers: copying a VIA also copies its complete in-flight transaction.
    class I2cBus
    {
        friend class StateCodec;
    public:
        explicit I2cBus(std::vector<Byte> addresses = {});
        bool enabled() const { return !addresses_.empty(); }
        bool sdaLow() const { return pullSdaLow_; }
        void reset(bool scl, bool sda);
        // Controller/external line levels before the targets' SDA contribution.
        void update(bool scl, bool sda);

    private:
        enum class Phase : Byte { idle, address, acknowledge, ignore };
        std::vector<Byte> addresses_;
        Phase phase_ = Phase::idle;
        Byte bits_ = 0, byte_ = 0;
        bool scl_ = true, sda_ = true, pullSdaLow_ = false;
    };
}
