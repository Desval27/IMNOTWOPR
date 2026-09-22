#pragma once
#include "joshua/memory.hpp"

namespace joshua
{
    struct Registers
    {
        Word pc = 0;
        Byte a = 0, x = 0, y = 0, sp = 0xff, p = 0x24;
    };

    class Cpu
    {
    public:
        explicit Cpu(Bus &bus) : bus_(bus) {}
        Registers r;
        void reset();
        std::uint64_t step();
        void nmi() { nmiPending_ = true; }
        bool waiting() const { return waiting_; }
        bool stopped() const { return stopped_; }

    private:
        enum Flag : Byte
        {
            C = 1,
            Z = 2,
            I = 4,
            D = 8,
            B = 16,
            U = 32,
            V = 64,
            N = 128
        };
        Bus &bus_;
        bool waiting_ = false, stopped_ = false, nmiPending_ = false;
        Byte fetch();
        void dummy();
        void push(Byte value);
        Byte pull();
        void flag(Flag f, bool value);
        void nz(Byte value);
        void interrupt(Word vector, bool software);
        void arithmetic(Byte value, bool subtract);
    };
}
