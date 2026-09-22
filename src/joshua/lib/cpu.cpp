#include "joshua/cpu.hpp"
#include "joshua/instruction.hpp"
#include <stdexcept>

namespace joshua
{
    Byte Cpu::fetch() { return bus_.read(r.pc++); }
    void Cpu::dummy() { bus_.read(r.pc); }
    void Cpu::push(Byte value) { bus_.write(0x100 | r.sp--, value); }
    Byte Cpu::pull() { return bus_.read(0x100 | ++r.sp); }
    void Cpu::flag(Flag f, bool value) { r.p = (value ? r.p | f : r.p & ~f) | U; }
    void Cpu::nz(Byte value)
    {
        flag(Z, value == 0);
        flag(N, value & 0x80);
    }
    void Cpu::reset()
    {
        waiting_ = stopped_ = nmiPending_ = false;
        dummy();
        dummy();
        for (int i = 0; i < 3; ++i)
            bus_.read(0x100 | r.sp--);
        flag(I, true);
        flag(D, false);
        auto lo = bus_.read(0xfffc);
        r.pc = lo | (bus_.read(0xfffd) << 8);
    }
    void Cpu::interrupt(Word vector, bool software)
    {
        push(static_cast<Byte>(r.pc >> 8));
        push(static_cast<Byte>(r.pc));
        push((r.p & ~B) | U | (software ? B : 0));
        flag(I, true);
        flag(D, false);
        auto lo = bus_.read(vector);
        r.pc = lo | (bus_.read(vector + 1) << 8);
    }
    void Cpu::arithmetic(Byte value, bool subtract)
    {
        int carry = r.p & C;
        int a = r.a;
        int binary = subtract ? a - value - (1 - carry) : a + value + carry;
        if (!(r.p & D))
        {
            flag(V, subtract ? ((a ^ value) & (a ^ binary) & 0x80) : (~(a ^ value) & (a ^ binary) & 0x80));
            flag(C, subtract ? binary >= 0 : binary > 255);
            r.a = static_cast<Byte>(binary);
        }
        else
        {
            if (subtract)
            {
                flag(V, (a ^ value) & (a ^ binary) & 0x80);
                int low = (a & 15) - (value & 15) - (1 - carry);
                int result = binary;
                if (low < 0)
                    result -= 6;
                if (binary < 0)
                    result -= 0x60;
                flag(C, binary >= 0);
                r.a = static_cast<Byte>(result);
            }
            else
            {
                int low = (a & 15) + (value & 15) + carry;
                if (low > 9)
                    low = ((low + 6) & 15) + 16;
                int result = (a & 0xf0) + (value & 0xf0) + low;
                flag(V, ~(a ^ value) & (a ^ result) & 0x80);
                if (result > 0x9f)
                    result += 0x60;
                flag(C, result > 255);
                r.a = static_cast<Byte>(result);
            }
        }
        nz(r.a);
    }
    std::uint64_t Cpu::step()
    {
        auto start = bus_.cycles();
        if (stopped_)
            return 0;
        if (waiting_)
        {
            if (!nmiPending_ && !bus_.irq())
            {
                bus_.idle();
                return 1;
            }
            waiting_ = false;
        }
        if (nmiPending_ || (bus_.irq() && !(r.p & I)))
        {
            auto vector = nmiPending_ ? 0xfffa : 0xfffe;
            nmiPending_ = false;
            bus_.read(r.pc, true);
            dummy();
            interrupt(vector, false);
            return bus_.cycles() - start;
        }
        auto opcode = bus_.read(r.pc++, true);
        const auto &instruction = instructions()[opcode];
        auto op = instruction.name;
        auto mode = instruction.mode;
        if (instruction.nopCycles)
        {
            Byte lo = 0;
            if (instruction.bytes > 1)
                lo = fetch();
            if (instruction.bytes > 2)
                fetch();
            if (mode == Mode::zp)
                bus_.read(lo);
            else if (mode == Mode::zpx)
            {
                bus_.read(lo);
                bus_.read(static_cast<Byte>(lo + r.x));
            }
            else
                while (bus_.cycles() - start < instruction.nopCycles)
                    bus_.read(instruction.bytes == 3 ? static_cast<Word>(r.pc - 1) : r.pc);
            return bus_.cycles() - start;
        }
        if (op == "BRK")
        {
            fetch();
            interrupt(0xfffe, true);
        }
        else if (op == "JSR")
        {
            Byte lo = fetch();
            bus_.read(0x100 | r.sp);
            push(static_cast<Byte>(r.pc >> 8));
            push(static_cast<Byte>(r.pc));
            r.pc = lo | (fetch() << 8);
        }
        else if (op == "RTS" || op == "RTI")
        {
            dummy();
            bus_.read(0x100 | r.sp);
            if (op == "RTI")
                r.p = (pull() & ~B) | U;
            Byte lo = pull();
            r.pc = lo | (pull() << 8);
            if (op == "RTS")
            {
                dummy();
                ++r.pc;
            }
        }
        else if (op == "PHA" || op == "PHP" || op == "PHX" || op == "PHY")
        {
            dummy();
            push(op == "PHA" ? r.a : op == "PHX" ? r.x
                                 : op == "PHY"   ? r.y
                                                 : r.p | B | U);
        }
        else if (op == "PLA" || op == "PLP" || op == "PLX" || op == "PLY")
        {
            dummy();
            bus_.read(0x100 | r.sp);
            Byte value = pull();
            if (op == "PLP")
                r.p = (value & ~B) | U;
            else
            {
                if (op == "PLA")
                    r.a = value;
                else if (op == "PLX")
                    r.x = value;
                else
                    r.y = value;
                nz(value);
            }
        }
        else if (mode == Mode::relative || mode == Mode::bitBranch)
        {
            bool take = false;
            if (mode == Mode::bitBranch)
            {
                Byte zp = fetch();
                Byte value = bus_.read(zp);
                bus_.read(zp);
                take = ((value >> (op[3] - '0')) & 1) == (op.starts_with("BBS") ? 1 : 0);
            }
            else
            {
                take = op == "BRA" || (op == "BCC" && !(r.p & C)) || (op == "BCS" && (r.p & C)) ||
                       (op == "BNE" && !(r.p & Z)) || (op == "BEQ" && (r.p & Z)) ||
                       (op == "BPL" && !(r.p & N)) || (op == "BMI" && (r.p & N)) ||
                       (op == "BVC" && !(r.p & V)) || (op == "BVS" && (r.p & V));
            }
            auto offset = static_cast<std::int8_t>(fetch());
            if (take)
            {
                dummy();
                Word target = static_cast<Word>(r.pc + offset);
                if ((target & 0xff00) != (r.pc & 0xff00))
                    bus_.read(mode == Mode::bitBranch ? r.pc : static_cast<Word>((r.pc & 0xff00) | (target & 0xff)));
                r.pc = target;
            }
        }
        else if (mode == Mode::implied)
        {
            dummy();
            if (op == "CLC")
                flag(C, false);
            else if (op == "SEC")
                flag(C, true);
            else if (op == "CLI")
                flag(I, false);
            else if (op == "SEI")
                flag(I, true);
            else if (op == "CLD")
                flag(D, false);
            else if (op == "SED")
                flag(D, true);
            else if (op == "CLV")
                flag(V, false);
            else if (op == "TAX")
            {
                r.x = r.a;
                nz(r.x);
            }
            else if (op == "TAY")
            {
                r.y = r.a;
                nz(r.y);
            }
            else if (op == "TXA")
            {
                r.a = r.x;
                nz(r.a);
            }
            else if (op == "TYA")
            {
                r.a = r.y;
                nz(r.a);
            }
            else if (op == "TSX")
            {
                r.x = r.sp;
                nz(r.x);
            }
            else if (op == "TXS")
                r.sp = r.x;
            else if (op == "DEX")
                nz(--r.x);
            else if (op == "DEY")
                nz(--r.y);
            else if (op == "INX")
                nz(++r.x);
            else if (op == "INY")
                nz(++r.y);
            else if (op == "WAI")
            {
                dummy();
                waiting_ = true;
            }
            else if (op == "STP")
            {
                dummy();
                stopped_ = true;
            }
            else
                throw std::runtime_error("unimplemented implied opcode");
        }
        else
        {
            bool store = op == "STA" || op == "STX" || op == "STY" || op == "STZ";
            bool modify = op == "ASL" || op == "LSR" || op == "ROL" || op == "ROR" || op == "INC" || op == "DEC" ||
                          op == "TRB" || op == "TSB" || op.starts_with("RMB") || op.starts_with("SMB");
            Word address = 0;
            Byte value = 0;
            if (mode == Mode::accumulator)
            {
                dummy();
                value = r.a;
            }
            else if (mode == Mode::immediate)
                value = fetch();
            else
            {
                Byte lo = fetch();
                if (mode == Mode::zp)
                    address = lo;
                else if (mode == Mode::zpx || mode == Mode::zpy)
                {
                    bus_.read(lo);
                    address = static_cast<Byte>(lo + (mode == Mode::zpx ? r.x : r.y));
                }
                else if (mode == Mode::indx || mode == Mode::indy || mode == Mode::indirectZp)
                {
                    if (mode == Mode::indx)
                    {
                        bus_.read(lo);
                        lo += r.x;
                    }
                    Byte low = bus_.read(lo);
                    address = low | (bus_.read(static_cast<Byte>(lo + 1)) << 8);
                    if (mode == Mode::indy)
                    {
                        Word base = address;
                        address += r.y;
                        if (store || ((base ^ address) & 0xff00))
                            bus_.read(static_cast<Word>(r.pc - 1));
                    }
                }
                else
                {
                    address = lo | (fetch() << 8);
                    if (mode == Mode::absx || mode == Mode::absy)
                    {
                        Word base = address;
                        address += mode == Mode::absx ? r.x : r.y;
                        if (store || op == "INC" || op == "DEC" || ((base ^ address) & 0xff00))
                            bus_.read(static_cast<Word>(r.pc - 1));
                    }
                    else if (mode == Mode::indirect || mode == Mode::indirectX)
                    {
                        if (mode == Mode::indirectX)
                        {
                            bus_.read(static_cast<Word>(r.pc - 2));
                            address += r.x;
                        }
                        Byte low = bus_.read(address);
                        if (mode == Mode::indirect)
                            bus_.read(static_cast<Word>((address & 0xff00) | static_cast<Byte>(address + 1)));
                        address = low | (bus_.read(static_cast<Word>(address + 1)) << 8);
                    }
                }
                if (op != "JMP" && !store)
                    value = bus_.read(address);
            }
            if (op == "JMP")
                r.pc = address;
            else if (store)
                bus_.write(address, op == "STA" ? r.a : op == "STX" ? r.x
                                                    : op == "STY"   ? r.y
                                                                    : 0);
            else if (modify)
            {
                if (mode != Mode::accumulator)
                    bus_.read(address);
                bool carry = r.p & C;
                if (op == "ASL" || op == "ROL")
                {
                    flag(C, value & 0x80);
                    value = static_cast<Byte>((value << 1) | (op == "ROL" && carry));
                    nz(value);
                }
                else if (op == "LSR" || op == "ROR")
                {
                    flag(C, value & 1);
                    value = (value >> 1) | ((op == "ROR" && carry) ? 0x80 : 0);
                    nz(value);
                }
                else if (op == "INC")
                    nz(++value);
                else if (op == "DEC")
                    nz(--value);
                else if (op == "TRB" || op == "TSB")
                {
                    flag(Z, !(value & r.a));
                    value = op == "TRB" ? value & ~r.a : value | r.a;
                }
                else if (op.starts_with("RMB"))
                    value &= ~(1 << (op[3] - '0'));
                else
                    value |= 1 << (op[3] - '0');
                if (mode == Mode::accumulator)
                    r.a = value;
                else
                    bus_.write(address, value);
            }
            else if (op == "LDA")
            {
                r.a = value;
                nz(value);
            }
            else if (op == "LDX")
            {
                r.x = value;
                nz(value);
            }
            else if (op == "LDY")
            {
                r.y = value;
                nz(value);
            }
            else if (op == "AND")
                nz(r.a &= value);
            else if (op == "ORA")
                nz(r.a |= value);
            else if (op == "EOR")
                nz(r.a ^= value);
            else if (op == "ADC" || op == "SBC")
            {
                if (r.p & D)
                    bus_.read(mode == Mode::immediate ? (op == "ADC" ? 0x7f : 0x00) : address);
                arithmetic(value, op == "SBC");
            }
            else if (op == "CMP" || op == "CPX" || op == "CPY")
            {
                auto reg = op == "CMP" ? r.a : op == "CPX" ? r.x
                                                           : r.y;
                flag(C, reg >= value);
                nz(static_cast<Byte>(reg - value));
            }
            else if (op == "BIT")
            {
                flag(Z, !(r.a & value));
                if (mode != Mode::immediate)
                {
                    flag(N, value & 0x80);
                    flag(V, value & 0x40);
                }
            }
            else
                throw std::runtime_error("unimplemented opcode");
        }
        return bus_.cycles() - start;
    }
}
