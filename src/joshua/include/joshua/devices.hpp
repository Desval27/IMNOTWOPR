#pragma once
#include "joshua/memory.hpp"
#include "joshua/serial.hpp"
#include <array>
#include <deque>
#include <optional>

namespace joshua
{
    class Via final : public Device
    {
    public:
        Byte peek(Word offset) const override;
        Byte read(Word offset) override;
        void write(Word offset, Byte value) override;
        void tick() override;
        void reset() override;
        bool irq() const override { return (ifr_ & ier_ & 0x7f) != 0; }
        void setPortA(Byte value) { inputA_ = value; }
        void setPortB(Byte value);

    private:
        std::array<Byte, 16> registers_{};
        Word t1_ = 0xffff, t2_ = 0xffff, latch1_ = 0xffff;
        Byte latch2Low_ = 0xff, ifr_ = 0, ier_ = 0;
        Byte inputA_ = 0xff, inputB_ = 0xff;
        bool armed1_ = false, armed2_ = false, pb7_ = true;
        bool delay1_ = false, delay2_ = false, reload1_ = false;
        void count2();
    };

    // Byte endpoint with emulated frame duration; the N variant's TDRE is always set.
    class Acia final : public Device
    {
    public:
        explicit Acia(std::uint32_t clockHz, SerialSettings peer = {});
        Byte peek(Word offset) const override;
        Byte read(Word offset) override;
        void write(Word offset, Byte value) override;
        void tick() override;
        void reset() override;
        bool irq() const override { return interrupt_; }
        void receive(Byte value);
        std::optional<Byte> takeTransmitted();
        std::uint64_t overwrittenTransmits() const { return overwritten_; }
        const SerialSettings &peerSettings() const { return peer_; }
        void setPeerSettings(const SerialSettings &settings);

    private:
        std::uint64_t transmitFrameCycles() const;
        std::uint32_t clockHz_;
        SerialSettings peer_;
        Byte command_ = 0, control_ = 0, received_ = 0, transmit_ = 0;
        Byte incoming_ = 0;
        bool full_ = false, overrun_ = false, interrupt_ = false;
        std::uint64_t txRemaining_ = 0, rxRemaining_ = 0, overwritten_ = 0;
        std::deque<Byte> input_, output_;
    };
}
