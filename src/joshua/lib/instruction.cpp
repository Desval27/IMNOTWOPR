#include "joshua/instruction.hpp"
#include <algorithm>
#include <charconv>
#include <cctype>
#include <iomanip>
#include <sstream>
#include <stdexcept>

namespace joshua
{
    std::uint32_t number(std::string_view text, std::uint32_t maximum, int base)
    {
        if (text.starts_with('$'))
        {
            base = 16;
            text.remove_prefix(1);
        }
        else if (text.size() > 2 && text[0] == '0')
        {
            switch (std::tolower(static_cast<unsigned char>(text[1])))
            {
            case 'x':
                base = 16;
                text.remove_prefix(2);
                break;
            case 'd':
                base = 10;
                text.remove_prefix(2);
                break;
            case 'o':
                base = 8;
                text.remove_prefix(2);
                break;
            case 'b':
                base = 2;
                text.remove_prefix(2);
                break;
            default:
                break;
            }
        }
        std::uint32_t result = 0;
        auto [end, error] = std::from_chars(text.data(), text.data() + text.size(), result, base);
        if (text.empty() || error != std::errc{} || end != text.data() + text.size() || result > maximum)
            throw std::runtime_error("invalid or out-of-range number: " + std::string(text));
        return result;
    }
    std::string hex(std::uint64_t value, unsigned width)
    {
        std::ostringstream out;
        out << std::uppercase << std::hex << std::setfill('0') << std::setw(static_cast<int>(width)) << value;
        return out.str();
    }
    std::string disassemble(const Bus &bus, Word address)
    {
        const auto opcode = bus.peek(address);
        const auto &i = instructions()[opcode];
        if (i.nopCycles && opcode != 0xea)
            return ".BYTE $" + hex(opcode, 2);
        Byte lo = bus.peek(static_cast<Word>(address + 1));
        Word value = lo | (bus.peek(static_cast<Word>(address + 2)) << 8);
        auto z = "$" + hex(lo, 2), a = "$" + hex(value);
        std::string operand;
        switch (i.mode)
        {
        case Mode::implied:
            break;
        case Mode::accumulator:
            operand = "A";
            break;
        case Mode::immediate:
            operand = "#" + z;
            break;
        case Mode::zp:
            operand = z;
            break;
        case Mode::zpx:
            operand = z + ",X";
            break;
        case Mode::zpy:
            operand = z + ",Y";
            break;
        case Mode::absolute:
            operand = a;
            break;
        case Mode::absx:
            operand = a + ",X";
            break;
        case Mode::absy:
            operand = a + ",Y";
            break;
        case Mode::indx:
            operand = "(" + z + ",X)";
            break;
        case Mode::indy:
            operand = "(" + z + "),Y";
            break;
        case Mode::indirectZp:
            operand = "(" + z + ")";
            break;
        case Mode::indirect:
            operand = "(" + a + ")";
            break;
        case Mode::indirectX:
            operand = "(" + a + ",X)";
            break;
        case Mode::relative:
            operand = "$" + hex(static_cast<Word>(address + 2 + static_cast<std::int8_t>(lo)));
            break;
        case Mode::bitBranch:
            operand = z + ",$" + hex(static_cast<Word>(address + 3 + static_cast<std::int8_t>(value >> 8)));
            break;
        }
        return std::string(i.name) + (operand.empty() ? "" : " " + operand);
    }
    std::vector<Byte> assemble(Word address, std::string text)
    {
        if (auto comment = text.find(';'); comment != std::string::npos)
            text.resize(comment);
        std::transform(text.begin(), text.end(), text.begin(), [](unsigned char c)
                       { return std::toupper(c); });
        std::istringstream in(text);
        std::string mnemonic, operand;
        in >> mnemonic;
        std::getline(in, operand);
        std::erase_if(operand, [](unsigned char c)
                      { return std::isspace(c); });
        if (mnemonic == ".BYTE")
            return {static_cast<Byte>(number(operand, 255))};
        Mode mode = Mode::implied;
        std::uint32_t value = 0, target = 0;
        const bool branch = mnemonic == "BRA" || mnemonic == "BCC" || mnemonic == "BCS" ||
                            mnemonic == "BEQ" || mnemonic == "BNE" || mnemonic == "BMI" || mnemonic == "BPL" ||
                            mnemonic == "BVC" || mnemonic == "BVS";
        auto parse = [&](std::size_t start, std::size_t end)
        { return number(std::string_view(operand).substr(start, end - start)); };
        if (operand == "A")
            mode = Mode::accumulator;
        else if (branch)
        {
            mode = Mode::relative;
            target = number(operand);
        }
        else if (mnemonic.starts_with("BBR") || mnemonic.starts_with("BBS"))
        {
            auto comma = operand.find(',');
            if (comma == std::string::npos)
                throw std::runtime_error("bit branch needs zero-page address,target");
            mode = Mode::bitBranch;
            value = number(operand.substr(0, comma), 255);
            target = number(operand.substr(comma + 1));
        }
        else if (!operand.empty())
        {
            if (operand[0] == '#')
            {
                mode = Mode::immediate;
                value = number(operand.substr(1), 255);
            }
            else if (operand[0] == '(')
            {
                if (operand.ends_with(",X)"))
                {
                    mode = mnemonic == "JMP" ? Mode::indirectX : Mode::indx;
                    value = parse(1, operand.size() - 3);
                }
                else if (operand.ends_with("),Y"))
                {
                    mode = Mode::indy;
                    value = parse(1, operand.size() - 3);
                }
                else if (operand.ends_with(')'))
                {
                    mode = mnemonic == "JMP" ? Mode::indirect : Mode::indirectZp;
                    value = parse(1, operand.size() - 1);
                }
                else
                    throw std::runtime_error("invalid indirect operand");
            }
            else
            {
                bool x = operand.ends_with(",X"), y = operand.ends_with(",Y");
                auto literal = operand.substr(0, operand.size() - (x || y ? 2 : 0));
                value = number(literal);
                // Four hexadecimal digits explicitly select absolute addressing.
                bool wide = value > 255 || (literal.starts_with('$') && literal.size() > 3) ||
                            (literal.starts_with("0X") && literal.size() > 4) || literal.size() == 4;
                if (mnemonic == "JMP" || mnemonic == "JSR")
                    wide = true;
                mode = x ? (wide ? Mode::absx : Mode::zpx) : y ? (wide ? Mode::absy : Mode::zpy)
                                                               : (wide ? Mode::absolute : Mode::zp);
            }
        }
        else if (mnemonic == "ASL" || mnemonic == "LSR" || mnemonic == "ROL" || mnemonic == "ROR" || mnemonic == "INC" || mnemonic == "DEC")
            mode = Mode::accumulator;
        auto lookup = [&](Mode wanted) -> int
        {
            for (int op = 0; op < 256; ++op)
            {
                auto &i = instructions()[op];
                if (i.name == mnemonic && i.mode == wanted && (!i.nopCycles || op == 0xea))
                    return op;
            }
            return -1;
        };
        int opcode = lookup(mode);
        if (opcode < 0)
        {
            if (mode == Mode::zp)
                mode = Mode::absolute;
            else if (mode == Mode::zpx)
                mode = Mode::absx;
            else if (mode == Mode::zpy)
                mode = Mode::absy;
            opcode = lookup(mode);
        }
        if (opcode < 0)
            throw std::runtime_error("unknown instruction or unsupported addressing mode");
        auto size = instructions()[opcode].bytes;
        if (mode == Mode::relative || mode == Mode::bitBranch)
        {
            Word delta = static_cast<Word>(target - static_cast<Word>(address + size));
            if (delta > 127 && delta < 0xff80)
                throw std::runtime_error("branch target is outside -128..127 bytes");
            if (mode == Mode::relative)
                value = delta & 255;
            else
                value |= (delta & 255) << 8;
        }
        else if (size == 2 && value > 255)
            throw std::runtime_error("operand must fit in one byte");
        std::vector<Byte> result{static_cast<Byte>(opcode)};
        if (size > 1)
            result.push_back(static_cast<Byte>(value));
        if (size > 2)
            result.push_back(static_cast<Byte>(value >> 8));
        return result;
    }
}

namespace joshua
{
    const std::array<Instruction, 256> &instructions()
    {
        static constexpr std::array<Instruction, 256> table{{
            {"BRK", Mode::implied, 1, 0},
            {"ORA", Mode::indx, 2, 0},
            {"NOP", Mode::immediate, 2, 2},
            {"NOP", Mode::implied, 1, 1},
            {"TSB", Mode::zp, 2, 0},
            {"ORA", Mode::zp, 2, 0},
            {"ASL", Mode::zp, 2, 0},
            {"RMB0", Mode::zp, 2, 0},
            {"PHP", Mode::implied, 1, 0},
            {"ORA", Mode::immediate, 2, 0},
            {"ASL", Mode::accumulator, 1, 0},
            {"NOP", Mode::implied, 1, 1},
            {"TSB", Mode::absolute, 3, 0},
            {"ORA", Mode::absolute, 3, 0},
            {"ASL", Mode::absolute, 3, 0},
            {"BBR0", Mode::bitBranch, 3, 0},
            {"BPL", Mode::relative, 2, 0},
            {"ORA", Mode::indy, 2, 0},
            {"ORA", Mode::indirectZp, 2, 0},
            {"NOP", Mode::implied, 1, 1},
            {"TRB", Mode::zp, 2, 0},
            {"ORA", Mode::zpx, 2, 0},
            {"ASL", Mode::zpx, 2, 0},
            {"RMB1", Mode::zp, 2, 0},
            {"CLC", Mode::implied, 1, 0},
            {"ORA", Mode::absy, 3, 0},
            {"INC", Mode::accumulator, 1, 0},
            {"NOP", Mode::implied, 1, 1},
            {"TRB", Mode::absolute, 3, 0},
            {"ORA", Mode::absx, 3, 0},
            {"ASL", Mode::absx, 3, 0},
            {"BBR1", Mode::bitBranch, 3, 0},
            {"JSR", Mode::absolute, 3, 0},
            {"AND", Mode::indx, 2, 0},
            {"NOP", Mode::immediate, 2, 2},
            {"NOP", Mode::implied, 1, 1},
            {"BIT", Mode::zp, 2, 0},
            {"AND", Mode::zp, 2, 0},
            {"ROL", Mode::zp, 2, 0},
            {"RMB2", Mode::zp, 2, 0},
            {"PLP", Mode::implied, 1, 0},
            {"AND", Mode::immediate, 2, 0},
            {"ROL", Mode::accumulator, 1, 0},
            {"NOP", Mode::implied, 1, 1},
            {"BIT", Mode::absolute, 3, 0},
            {"AND", Mode::absolute, 3, 0},
            {"ROL", Mode::absolute, 3, 0},
            {"BBR2", Mode::bitBranch, 3, 0},
            {"BMI", Mode::relative, 2, 0},
            {"AND", Mode::indy, 2, 0},
            {"AND", Mode::indirectZp, 2, 0},
            {"NOP", Mode::implied, 1, 1},
            {"BIT", Mode::zpx, 2, 0},
            {"AND", Mode::zpx, 2, 0},
            {"ROL", Mode::zpx, 2, 0},
            {"RMB3", Mode::zp, 2, 0},
            {"SEC", Mode::implied, 1, 0},
            {"AND", Mode::absy, 3, 0},
            {"DEC", Mode::accumulator, 1, 0},
            {"NOP", Mode::implied, 1, 1},
            {"BIT", Mode::absx, 3, 0},
            {"AND", Mode::absx, 3, 0},
            {"ROL", Mode::absx, 3, 0},
            {"BBR3", Mode::bitBranch, 3, 0},
            {"RTI", Mode::implied, 1, 0},
            {"EOR", Mode::indx, 2, 0},
            {"NOP", Mode::immediate, 2, 2},
            {"NOP", Mode::implied, 1, 1},
            {"NOP", Mode::zp, 2, 3},
            {"EOR", Mode::zp, 2, 0},
            {"LSR", Mode::zp, 2, 0},
            {"RMB4", Mode::zp, 2, 0},
            {"PHA", Mode::implied, 1, 0},
            {"EOR", Mode::immediate, 2, 0},
            {"LSR", Mode::accumulator, 1, 0},
            {"NOP", Mode::implied, 1, 1},
            {"JMP", Mode::absolute, 3, 0},
            {"EOR", Mode::absolute, 3, 0},
            {"LSR", Mode::absolute, 3, 0},
            {"BBR4", Mode::bitBranch, 3, 0},
            {"BVC", Mode::relative, 2, 0},
            {"EOR", Mode::indy, 2, 0},
            {"EOR", Mode::indirectZp, 2, 0},
            {"NOP", Mode::implied, 1, 1},
            {"NOP", Mode::zpx, 2, 4},
            {"EOR", Mode::zpx, 2, 0},
            {"LSR", Mode::zpx, 2, 0},
            {"RMB5", Mode::zp, 2, 0},
            {"CLI", Mode::implied, 1, 0},
            {"EOR", Mode::absy, 3, 0},
            {"PHY", Mode::implied, 1, 0},
            {"NOP", Mode::implied, 1, 1},
            {"NOP", Mode::absolute, 3, 8},
            {"EOR", Mode::absx, 3, 0},
            {"LSR", Mode::absx, 3, 0},
            {"BBR5", Mode::bitBranch, 3, 0},
            {"RTS", Mode::implied, 1, 0},
            {"ADC", Mode::indx, 2, 0},
            {"NOP", Mode::immediate, 2, 2},
            {"NOP", Mode::implied, 1, 1},
            {"STZ", Mode::zp, 2, 0},
            {"ADC", Mode::zp, 2, 0},
            {"ROR", Mode::zp, 2, 0},
            {"RMB6", Mode::zp, 2, 0},
            {"PLA", Mode::implied, 1, 0},
            {"ADC", Mode::immediate, 2, 0},
            {"ROR", Mode::accumulator, 1, 0},
            {"NOP", Mode::implied, 1, 1},
            {"JMP", Mode::indirect, 3, 0},
            {"ADC", Mode::absolute, 3, 0},
            {"ROR", Mode::absolute, 3, 0},
            {"BBR6", Mode::bitBranch, 3, 0},
            {"BVS", Mode::relative, 2, 0},
            {"ADC", Mode::indy, 2, 0},
            {"ADC", Mode::indirectZp, 2, 0},
            {"NOP", Mode::implied, 1, 1},
            {"STZ", Mode::zpx, 2, 0},
            {"ADC", Mode::zpx, 2, 0},
            {"ROR", Mode::zpx, 2, 0},
            {"RMB7", Mode::zp, 2, 0},
            {"SEI", Mode::implied, 1, 0},
            {"ADC", Mode::absy, 3, 0},
            {"PLY", Mode::implied, 1, 0},
            {"NOP", Mode::implied, 1, 1},
            {"JMP", Mode::indirectX, 3, 0},
            {"ADC", Mode::absx, 3, 0},
            {"ROR", Mode::absx, 3, 0},
            {"BBR7", Mode::bitBranch, 3, 0},
            {"BRA", Mode::relative, 2, 0},
            {"STA", Mode::indx, 2, 0},
            {"NOP", Mode::immediate, 2, 2},
            {"NOP", Mode::implied, 1, 1},
            {"STY", Mode::zp, 2, 0},
            {"STA", Mode::zp, 2, 0},
            {"STX", Mode::zp, 2, 0},
            {"SMB0", Mode::zp, 2, 0},
            {"DEY", Mode::implied, 1, 0},
            {"BIT", Mode::immediate, 2, 0},
            {"TXA", Mode::implied, 1, 0},
            {"NOP", Mode::implied, 1, 1},
            {"STY", Mode::absolute, 3, 0},
            {"STA", Mode::absolute, 3, 0},
            {"STX", Mode::absolute, 3, 0},
            {"BBS0", Mode::bitBranch, 3, 0},
            {"BCC", Mode::relative, 2, 0},
            {"STA", Mode::indy, 2, 0},
            {"STA", Mode::indirectZp, 2, 0},
            {"NOP", Mode::implied, 1, 1},
            {"STY", Mode::zpx, 2, 0},
            {"STA", Mode::zpx, 2, 0},
            {"STX", Mode::zpy, 2, 0},
            {"SMB1", Mode::zp, 2, 0},
            {"TYA", Mode::implied, 1, 0},
            {"STA", Mode::absy, 3, 0},
            {"TXS", Mode::implied, 1, 0},
            {"NOP", Mode::implied, 1, 1},
            {"STZ", Mode::absolute, 3, 0},
            {"STA", Mode::absx, 3, 0},
            {"STZ", Mode::absx, 3, 0},
            {"BBS1", Mode::bitBranch, 3, 0},
            {"LDY", Mode::immediate, 2, 0},
            {"LDA", Mode::indx, 2, 0},
            {"LDX", Mode::immediate, 2, 0},
            {"NOP", Mode::implied, 1, 1},
            {"LDY", Mode::zp, 2, 0},
            {"LDA", Mode::zp, 2, 0},
            {"LDX", Mode::zp, 2, 0},
            {"SMB2", Mode::zp, 2, 0},
            {"TAY", Mode::implied, 1, 0},
            {"LDA", Mode::immediate, 2, 0},
            {"TAX", Mode::implied, 1, 0},
            {"NOP", Mode::implied, 1, 1},
            {"LDY", Mode::absolute, 3, 0},
            {"LDA", Mode::absolute, 3, 0},
            {"LDX", Mode::absolute, 3, 0},
            {"BBS2", Mode::bitBranch, 3, 0},
            {"BCS", Mode::relative, 2, 0},
            {"LDA", Mode::indy, 2, 0},
            {"LDA", Mode::indirectZp, 2, 0},
            {"NOP", Mode::implied, 1, 1},
            {"LDY", Mode::zpx, 2, 0},
            {"LDA", Mode::zpx, 2, 0},
            {"LDX", Mode::zpy, 2, 0},
            {"SMB3", Mode::zp, 2, 0},
            {"CLV", Mode::implied, 1, 0},
            {"LDA", Mode::absy, 3, 0},
            {"TSX", Mode::implied, 1, 0},
            {"NOP", Mode::implied, 1, 1},
            {"LDY", Mode::absx, 3, 0},
            {"LDA", Mode::absx, 3, 0},
            {"LDX", Mode::absy, 3, 0},
            {"BBS3", Mode::bitBranch, 3, 0},
            {"CPY", Mode::immediate, 2, 0},
            {"CMP", Mode::indx, 2, 0},
            {"NOP", Mode::immediate, 2, 2},
            {"NOP", Mode::implied, 1, 1},
            {"CPY", Mode::zp, 2, 0},
            {"CMP", Mode::zp, 2, 0},
            {"DEC", Mode::zp, 2, 0},
            {"SMB4", Mode::zp, 2, 0},
            {"INY", Mode::implied, 1, 0},
            {"CMP", Mode::immediate, 2, 0},
            {"DEX", Mode::implied, 1, 0},
            {"WAI", Mode::implied, 1, 0},
            {"CPY", Mode::absolute, 3, 0},
            {"CMP", Mode::absolute, 3, 0},
            {"DEC", Mode::absolute, 3, 0},
            {"BBS4", Mode::bitBranch, 3, 0},
            {"BNE", Mode::relative, 2, 0},
            {"CMP", Mode::indy, 2, 0},
            {"CMP", Mode::indirectZp, 2, 0},
            {"NOP", Mode::implied, 1, 1},
            {"NOP", Mode::zpx, 2, 4},
            {"CMP", Mode::zpx, 2, 0},
            {"DEC", Mode::zpx, 2, 0},
            {"SMB5", Mode::zp, 2, 0},
            {"CLD", Mode::implied, 1, 0},
            {"CMP", Mode::absy, 3, 0},
            {"PHX", Mode::implied, 1, 0},
            {"STP", Mode::implied, 1, 0},
            {"NOP", Mode::absolute, 3, 4},
            {"CMP", Mode::absx, 3, 0},
            {"DEC", Mode::absx, 3, 0},
            {"BBS5", Mode::bitBranch, 3, 0},
            {"CPX", Mode::immediate, 2, 0},
            {"SBC", Mode::indx, 2, 0},
            {"NOP", Mode::immediate, 2, 2},
            {"NOP", Mode::implied, 1, 1},
            {"CPX", Mode::zp, 2, 0},
            {"SBC", Mode::zp, 2, 0},
            {"INC", Mode::zp, 2, 0},
            {"SMB6", Mode::zp, 2, 0},
            {"INX", Mode::implied, 1, 0},
            {"SBC", Mode::immediate, 2, 0},
            {"NOP", Mode::implied, 1, 2},
            {"NOP", Mode::implied, 1, 1},
            {"CPX", Mode::absolute, 3, 0},
            {"SBC", Mode::absolute, 3, 0},
            {"INC", Mode::absolute, 3, 0},
            {"BBS6", Mode::bitBranch, 3, 0},
            {"BEQ", Mode::relative, 2, 0},
            {"SBC", Mode::indy, 2, 0},
            {"SBC", Mode::indirectZp, 2, 0},
            {"NOP", Mode::implied, 1, 1},
            {"NOP", Mode::zpx, 2, 4},
            {"SBC", Mode::zpx, 2, 0},
            {"INC", Mode::zpx, 2, 0},
            {"SMB7", Mode::zp, 2, 0},
            {"SED", Mode::implied, 1, 0},
            {"SBC", Mode::absy, 3, 0},
            {"PLX", Mode::implied, 1, 0},
            {"NOP", Mode::implied, 1, 1},
            {"NOP", Mode::absolute, 3, 4},
            {"SBC", Mode::absx, 3, 0},
            {"INC", Mode::absx, 3, 0},
            {"BBS7", Mode::bitBranch, 3, 0},
        }};
        return table;
    }
}
