#include "joshua/devices.hpp"
#include <algorithm>
#include <cmath>
#include <stdexcept>

namespace joshua
{
    Byte Via::peek(Word offset) const
    {
        switch (offset & 15)
        {
        case 0:
        {
            Byte value = (registers_[0] & registers_[2]) | (inputB_ & ~registers_[2]);
            if (registers_[11] & 0x80)
                value = (value & 0x7f) | (pb7_ ? 0x80 : 0);
            return value;
        }
        case 1:
        case 15:
            return (registers_[1] & registers_[3]) | (inputA_ & ~registers_[3]);
        case 4:
            return static_cast<Byte>(t1_);
        case 5:
            return static_cast<Byte>(t1_ >> 8);
        case 6:
            return static_cast<Byte>(latch1_);
        case 7:
            return static_cast<Byte>(latch1_ >> 8);
        case 8:
            return static_cast<Byte>(t2_);
        case 9:
            return static_cast<Byte>(t2_ >> 8);
        case 13:
            return ifr_ | (irq() ? 0x80 : 0);
        case 14:
            return ier_ | 0x80;
        default:
            return registers_[offset & 15];
        }
    }
    Byte Via::read(Word offset)
    {
        auto result = peek(offset);
        switch (offset & 15)
        {
        case 0:
            ifr_ &= ~0x18;
            break;
        case 1:
            ifr_ &= ~0x03;
            break;
        case 4:
            ifr_ &= ~0x40;
            break;
        case 8:
            ifr_ &= ~0x20;
            break;
        case 10:
            ifr_ &= ~0x04;
            break;
        default:
            break;
        }
        return result;
    }
    void Via::write(Word offset, Byte value)
    {
        switch (offset & 15)
        {
        case 0:
            registers_[0] = value;
            ifr_ &= ~0x18;
            break;
        case 1:
            registers_[1] = value;
            ifr_ &= ~0x03;
            break;
        case 15:
            registers_[1] = value;
            break;
        case 4:
        case 6:
            latch1_ = (latch1_ & 0xff00) | value;
            break;
        case 5:
            latch1_ = (latch1_ & 0xff) | (value << 8);
            t1_ = latch1_;
            armed1_ = true;
            delay1_ = true;
            reload1_ = false;
            pb7_ = false;
            ifr_ &= ~0x40;
            break;
        case 7:
            latch1_ = (latch1_ & 0xff) | (value << 8);
            ifr_ &= ~0x40;
            break;
        case 8:
            latch2Low_ = value;
            break;
        case 9:
            t2_ = static_cast<Word>((value << 8) | latch2Low_);
            armed2_ = true;
            delay2_ = true;
            ifr_ &= ~0x20;
            break;
        case 11:
            if (value & 0x1f)
                throw std::runtime_error("VIA shift register and input latching modes are not implemented yet");
            registers_[11] = value;
            break;
        case 12:
            if (value)
                throw std::runtime_error("VIA control-line modes are not implemented yet");
            registers_[12] = value;
            break;
        case 13:
            ifr_ &= ~(value & 0x7f);
            break;
        case 14:
            if (value & 0x80)
                ier_ |= value & 0x7f;
            else
                ier_ &= ~value;
            break;
        default:
            registers_[offset & 15] = value;
            break;
        }
    }
    void Via::count2()
    {
        if (t2_-- == 0 && armed2_)
        {
            ifr_ |= 0x20;
            armed2_ = false;
        }
    }
    void Via::setPortB(Byte value)
    {
        if ((registers_[11] & 0x20) && (inputB_ & 0x40) && !(value & 0x40))
            count2();
        inputB_ = value;
    }
    void Via::tick()
    {
        if (delay1_)
            delay1_ = false;
        else if (reload1_)
        {
            t1_ = latch1_;
            reload1_ = false;
        }
        else if (t1_-- == 0)
        {
            reload1_ = true;
            if (armed1_)
            {
                ifr_ |= 0x40;
                if (registers_[11] & 0x40)
                    pb7_ = !pb7_;
                else
                {
                    armed1_ = false;
                    pb7_ = true;
                }
            }
        }
        if (delay2_)
            delay2_ = false;
        else if (!(registers_[11] & 0x20))
            count2();
    }
    void Via::reset()
    {
        registers_.fill(0);
        t1_ = t2_ = latch1_ = 0xffff;
        latch2Low_ = 0xff;
        ifr_ = ier_ = 0;
        armed1_ = armed2_ = delay1_ = delay2_ = reload1_ = false;
        pb7_ = true;
    }

    Acia::Acia(std::uint32_t clockHz, SerialSettings peer) : clockHz_(clockHz), peer_(peer)
    {
        peer_.validate();
    }
    void Acia::setPeerSettings(const SerialSettings &settings)
    {
        settings.validate();
        peer_ = settings;
    }
    Byte Acia::peek(Word offset) const
    {
        switch (offset & 3)
        {
        case 0:
            return received_;
        case 1:
            return 0x10 | (full_ ? 8 : 0) | (overrun_ ? 4 : 0) | (interrupt_ ? 0x80 : 0);
        case 2:
            return command_;
        default:
            return control_;
        }
    }
    Byte Acia::read(Word offset)
    {
        auto value = peek(offset);
        if ((offset & 3) == 0)
        {
            full_ = overrun_ = false;
        }
        if ((offset & 3) == 1)
            interrupt_ = false;
        return value;
    }
    void Acia::write(Word offset, Byte value)
    {
        switch (offset & 3)
        {
        case 0:
            if (txRemaining_)
                ++overwritten_;
            // Latch both endpoint widths for this frame; later reconfiguration
            // affects subsequent frames, not a byte already being transmitted.
            transmit_ = value & (0xff >> ((control_ >> 5) & 3)) & peer_.dataMask();
            // Bus ticks after writes: do not count that same edge as a bit interval.
            txRemaining_ = transmitFrameCycles() + 1;
            break;
        case 1:
            command_ &= 0xe0;
            overrun_ = interrupt_ = false;
            break;
        case 2:
            if ((value & 0x30) || (value & 0x0c) == 4 || (value & 0x0c) == 12)
                throw std::runtime_error("ACIA echo, parity, transmit IRQ and break modes are unsupported");
            command_ = value;
            if (!(value & 1) || (value & 2))
                interrupt_ = false;
            break;
        case 3:
            control_ = value;
            break;
        }
    }
    std::uint64_t Acia::transmitFrameCycles() const
    {
        static constexpr double baud[] = {115200, 50, 75, 109.92, 134.58, 150, 300, 600,
                                          1200, 1800, 2400, 3600, 4800, 7200, 9600, 19200};
        int bits = 8 - ((control_ >> 5) & 3);
        double stop = (control_ & 0x80) ? (bits == 5 ? 1.5 : 2.0) : 1.0;
        double rate = baud[control_ & 15];
        return std::max<std::uint64_t>(1, static_cast<std::uint64_t>(std::ceil(clockHz_ * (1 + bits + stop) / rate)));
    }
    void Acia::receive(Byte value)
    {
        if (input_.size() >= 65536)
            throw std::runtime_error("serial input queue is full");
        input_.push_back(value);
    }
    void Acia::tick()
    {
        if (txRemaining_ && (command_ & 1) && (command_ & 0x0c) == 8 && --txRemaining_ == 0)
            output_.push_back(transmit_);
        if (!(command_ & 1))
            return;
        if (!rxRemaining_ && !input_.empty())
        {
            // The connected terminal clocks its own transmitted frames. Keep the
            // guest's receiver width independent, and snapshot an in-flight byte.
            rxRemaining_ = peer_.frameCycles(clockHz_);
            incoming_ = input_.front() & peer_.dataMask() & (0xff >> ((control_ >> 5) & 3));
            input_.pop_front();
        }
        if (rxRemaining_ && --rxRemaining_ == 0)
        {
            if (full_)
                overrun_ = true;
            else
            {
                received_ = incoming_;
                full_ = true;
            }
            if (!(command_ & 2))
                interrupt_ = true;
        }
    }
    std::optional<Byte> Acia::takeTransmitted()
    {
        if (output_.empty())
            return std::nullopt;
        Byte value = output_.front();
        output_.pop_front();
        return value;
    }
    void Acia::reset()
    {
        command_ = control_ = received_ = transmit_ = incoming_ = 0;
        full_ = overrun_ = interrupt_ = false;
        txRemaining_ = rxRemaining_ = overwritten_ = 0;
        input_.clear();
        output_.clear();
    }
}
