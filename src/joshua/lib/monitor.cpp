#include "joshua/monitor.hpp"
#include "joshua/instruction.hpp"
#include <algorithm>
#include <cctype>
#include <iomanip>
#include <sstream>
#include <stdexcept>

namespace joshua
{
    namespace
    {
        std::vector<std::string> tokenize(const std::string &text)
        {
            std::vector<std::string> result;
            std::string token;
            bool quoted = false, started = false;
            for (char c : text)
            {
                if (c == '"')
                {
                    quoted = !quoted;
                    started = true;
                }
                else if (!quoted && c == ';')
                    break;
                else if (!quoted && std::isspace(static_cast<unsigned char>(c)))
                {
                    if (started)
                    {
                        result.push_back(token);
                        token.clear();
                        started = false;
                    }
                }
                else
                {
                    token += c;
                    started = true;
                }
            }
            if (quoted)
                throw std::runtime_error("unterminated quoted argument");
            if (started)
                result.push_back(token);
            return result;
        }
    }
    MonitorAction Monitor::execute(const std::string &line)
    {
        auto args = tokenize(line);
        if (args.empty())
            return MonitorAction::prompt;
        auto command = args.front();
        std::transform(command.begin(), command.end(), command.begin(), [](unsigned char c)
                       { return std::tolower(c); });
        auto arity = [&](std::size_t min, std::size_t max)
        {
            if (args.size() < min || args.size() > max)
                throw std::runtime_error("wrong number of arguments; type help");
        };
        auto n = [&](std::size_t index, std::uint32_t max = 65535)
        { return number(args.at(index), max); };
        // A bare second address is inclusive; only L introduces a count.
        auto range = [&](std::uint32_t address, std::uint32_t defaultCount)
        {
            struct Range
            {
                bool ending;
                std::uint32_t value;
            };
            if (args.size() <= 2)
                return Range{false, defaultCount};
            if (args[2] == "L" || args[2] == "l")
            {
                if (args.size() != 4)
                    throw std::runtime_error("expected L COUNT");
                return Range{false, n(3, 65536)};
            }
            if (args.size() != 3)
                throw std::runtime_error("expected END or L COUNT");
            auto end = n(2);
            if (end < address)
                throw std::runtime_error("ending address precedes starting address");
            return Range{true, end};
        };
        auto &bus = machine_.bus;
        auto &cpu = machine_.cpu;
        if (command == "help" || command == "?")
        {
            arity(1, 1);
            out_ << help();
        }
        else if (command == "quit" || command == "exit" || command == "q")
        {
            arity(1, 1);
            return MonitorAction::quit;
        }
        else if (command == "regs" || command == "r")
        {
            arity(1, 3);
            if (args.size() == 2)
                throw std::runtime_error("usage: regs [pc|a|x|y|sp|p VALUE]");
            if (args.size() == 3)
            {
                auto reg = args[1];
                std::transform(reg.begin(), reg.end(), reg.begin(), [](unsigned char c)
                               { return std::tolower(c); });
                auto value = n(2, reg == "pc" ? 65535 : 255);
                if (reg == "pc")
                    cpu.r.pc = static_cast<Word>(value);
                else if (reg == "a")
                    cpu.r.a = static_cast<Byte>(value);
                else if (reg == "x")
                    cpu.r.x = static_cast<Byte>(value);
                else if (reg == "y")
                    cpu.r.y = static_cast<Byte>(value);
                else if (reg == "sp")
                    cpu.r.sp = static_cast<Byte>(value);
                else if (reg == "p")
                    cpu.r.p = (static_cast<Byte>(value) & ~0x10) | 0x20;
                else
                    throw std::runtime_error("unknown register");
            }
            out_ << machine_.status() << '\n';
        }
        else if (command == "mem" || command == "m")
        {
            arity(2, 4);
            const bool next = args[1] == "N" || args[1] == "n";
            auto address = next ? nextMemory_.value_or(cpu.r.pc) : n(1);
            auto requested = range(address, std::min(128u, 65536 - address));
            auto size = requested.ending ? requested.value - address + 1 : requested.value;
            if (size > 65536 - address)
                throw std::runtime_error("memory range exceeds $FFFF");
            for (std::uint32_t pos = 0; pos < size; pos += 16)
            {
                out_ << hex(address + pos) << "  ";
                for (unsigned j = 0; j < 16; ++j)
                    out_ << (pos + j < size ? hex(bus.peek(static_cast<Word>(address + pos + j)), 2) + " " : "   ");
                out_ << " |";
                for (unsigned j = 0; j < 16 && pos + j < size; ++j)
                {
                    Byte c = bus.peek(static_cast<Word>(address + pos + j));
                    out_ << (c >= 32 && c <= 126 ? static_cast<char>(c) : '.');
                }
                out_ << "|\n";
            }
            if (size)
                nextMemory_ = static_cast<Word>(address + size);
        }
        else if (command == "write" || command == "deposit" || command == "deposite" || command == "w")
        {
            arity(3, 65538);
            auto address = n(1);
            std::vector<Byte> values;
            for (std::size_t i = 2; i < args.size(); ++i)
                values.push_back(static_cast<Byte>(n(i, 255)));
            bus.patch(address, values);
        }
        else if (command == "dis" || command == "d")
        {
            arity(1, 4);
            const bool next = args.size() > 1 && (args[1] == "N" || args[1] == "n");
            std::uint32_t position = next              ? nextDisassembly_.value_or(cpu.r.pc)
                                     : args.size() > 1 ? n(1)
                                                       : cpu.r.pc;
            auto requested = range(position, 16);
            for (std::uint32_t i = 0; requested.ending ? position <= requested.value : i < requested.value; ++i)
            {
                Word address = static_cast<Word>(position);
                auto opcode = bus.peek(address);
                const auto &instruction = instructions()[opcode];
                unsigned size = instruction.nopCycles && opcode != 0xea ? 1 : instruction.bytes;
                out_ << hex(address) << "  ";
                for (unsigned j = 0; j < 3; ++j)
                    out_ << (j < size ? hex(bus.peek(static_cast<Word>(address + j)), 2) + " " : "   ");
                out_ << " " << disassemble(bus, address) << '\n';
                position += size;
                nextDisassembly_ = static_cast<Word>(position);
            }
        }
        else if (command == "asm" || command == "a")
        {
            arity(3, 10);
            Word address = static_cast<Word>(n(1));
            std::string source;
            for (std::size_t i = 2; i < args.size(); ++i)
                source += args[i] + " ";
            auto bytes = assemble(address, source);
            bus.patch(address, bytes);
            out_ << hex(address) << "  " << disassemble(bus, address) << "  next=$" << hex(static_cast<Word>(address + bytes.size())) << '\n';
        }
        else if (command == "load")
        {
            arity(3, 3);
            machine_.load(static_cast<Word>(n(2)), args[1]);
        }
        else if (command == "save")
        {
            arity(4, 4);
            machine_.save(static_cast<Word>(n(2)), n(3, 65536), args[1]);
        }
        else if (command == "map")
        {
            arity(1, 1);
            for (const auto &mapping : bus.mappings())
                out_ << hex(mapping.base) << '-' << hex(mapping.base + mapping.size - 1) << " " << mapping.name << '\n';
        }
        else if (command == "break" || command == "b")
        {
            arity(1, 4);
            auto &points = machine_.breakpoints;
            if (args.size() == 1)
            {
                if (points.empty())
                    out_ << "No breakpoints.\n";
                for (const auto &[address, enabled] : points)
                    out_ << hex(address) << (enabled ? " enabled\n" : " disabled\n");
            }
            else if (args.size() == 2)
                points[static_cast<Word>(n(1))] = true;
            else
            {
                Word address = static_cast<Word>(n(2));
                auto found = points.find(address);
                if (found == points.end())
                    throw std::runtime_error("no breakpoint at that address");
                if (args[1] == "delete" && args.size() == 3)
                    points.erase(found);
                else if (args[1] == "enable" && args.size() == 3)
                    found->second = true;
                else if (args[1] == "disable" && args.size() == 3)
                    found->second = false;
                else if (args[1] == "move" && args.size() == 4)
                {
                    Word destination = static_cast<Word>(n(3));
                    bool enabled = found->second;
                    if (points.contains(destination))
                        throw std::runtime_error("breakpoint already exists at destination");
                    points.erase(found);
                    points[destination] = enabled;
                }
                else
                    throw std::runtime_error("usage: break [ADDRESS | delete|enable|disable ADDRESS | move OLD NEW]");
            }
        }
        else if (command == "step" || command == "s" || command == "trace")
        {
            arity(1, 2);
            auto count = args.size() == 2 ? n(1, 1'000'000) : 1;
            if (cpu.stopped())
                throw std::runtime_error("CPU is stopped; reset is required");
            auto oldTrace = bus.trace;
            if (command == "trace")
                bus.trace = [&](const BusCycle &c)
                {
                    out_ << c.number << " " << (c.write ? 'W' : 'R') << " " << hex(c.address) << " " << hex(c.data, 2) << (c.sync ? " SYNC" : "") << '\n';
                };
            try
            {
                for (std::uint32_t i = 0; i < count && !cpu.stopped(); ++i)
                    cpu.step();
            }
            catch (...)
            {
                bus.trace = oldTrace;
                throw;
            }
            bus.trace = oldTrace;
            out_ << machine_.status() << '\n';
        }
        else if (command == "run" || command == "go" || command == "g" || command == "continue" || command == "c")
        {
            arity(1, 2);
            if (cpu.stopped())
                throw std::runtime_error("CPU is stopped; reset is required");
            if (args.size() == 2)
                cpu.r.pc = static_cast<Word>(n(1));
            return MonitorAction::run;
        }
        else if (command == "reset")
        {
            arity(1, 1);
            machine_.reset();
        }
        else if (command == "nmi")
        {
            arity(1, 1);
            cpu.nmi();
        }
        else if (command == "io")
        {
            arity(3, 4);
            if (args[1] == "read" && args.size() == 3)
                out_ << hex(bus.read(static_cast<Word>(n(2))), 2) << '\n';
            else if (args[1] == "write" && args.size() == 4)
            {
                Word address = static_cast<Word>(n(2));
                Byte value = static_cast<Byte>(n(3, 255));
                bus.write(address, value);
            }
            else
                throw std::runtime_error("usage: io read ADDRESS | io write ADDRESS BYTE");
        }
        else if (command == "serial")
        {
            arity(1, 5);
            if (args.size() != 1 && args.size() != 5)
                throw std::runtime_error("usage: serial [BAUD DATA PARITY STOP] (decimal settings)");
            if (!machine_.acia)
                throw std::runtime_error("no ACIA configured");
            if (args.size() == 5)
            {
                SerialSettings settings{number(args[1], 4'000'000, 10), number(args[2], 8, 10),
                                        parseParity(args[3]), parseStopBits(args[4])};
                machine_.acia->setPeerSettings(settings);
            }
            out_ << "Console serial: " << machine_.acia->peerSettings().description() << '\n';
        }
        else if (command == "console-newline")
        {
            arity(1, 2);
            if (args.size() == 2)
                machine_.consoleOutput.setMode(parseConsoleNewline(args[1]));
            out_ << "Console newline: " << consoleNewlineName(machine_.consoleOutput.mode()) << '\n';
        }
        else if (command == "send")
        {
            arity(2, 65537);
            if (!machine_.acia)
                throw std::runtime_error("no ACIA configured");
            std::vector<Byte> bytes;
            for (std::size_t i = 1; i < args.size(); ++i)
                bytes.push_back(static_cast<Byte>(n(i, 255)));
            for (auto byte : bytes)
                machine_.acia->receive(byte);
        }
        else
            throw std::runtime_error("unknown command; type help");
        return MonitorAction::prompt;
    }
    std::string Monitor::help()
    {
        return R"(Monitor numbers default to hexadecimal, including counts; serial settings use decimal.
Use $/0x hex, 0d decimal, 0o octal, or 0b binary. Quote paths with spaces.
  mem ADDRESS|N [END | L COUNT]   Hex bytes and printable ASCII (m)
  write ADDRESS BYTE ...          Patch RAM/ROM bytes (w, deposit, deposite)
  dis [ADDRESS|N [END | L COUNT]] Disassemble; default address is PC (d)
  asm ADDRESS INSTRUCTION         Assemble one instruction (a); no symbols/macros
  regs [REGISTER VALUE]           Show/edit pc,a,x,y,sp,p (r)
  break [ADDRESS]                 List/set execution breakpoints (b)
  break delete ADDRESS            Delete a breakpoint
  break enable|disable ADDRESS    Enable/disable a breakpoint
  break move OLD NEW              Change breakpoint address
  step [COUNT]                    Step instructions; WAI advances one idle cycle (s)
  trace [COUNT]                   Step and print individual bus accesses
  run [ADDRESS]                   Resume serial console (go,g,continue,c)
  reset                           Reset CPU/devices, retain RAM/ROM/breakpoints
  nmi                             Latch NMI for the next step/run
  load FILE ADDRESS               Load a raw binary into RAM/ROM
  save FILE ADDRESS COUNT         Save bytes to raw binary (replaces FILE)
  map                             Display configured regions
  io read ADDRESS                 Perform a real bus read, including side effects
  io write ADDRESS BYTE           Perform a real bus write, including side effects
  send BYTE ...                   Queue received serial bytes (also the escape byte)
  serial [BAUD DATA PARITY STOP]  Show/change console settings (default 19200 8 none 1)
  console-newline [MODE]          Show/change output newlines: raw, cr, lf, auto
  help                            Show this help (?)
  quit | exit                     Exit (q)
Examples:
  mem $0200 $023F
  mem $0200 L 40
  mem N L 40
  dis $0200 L 10
  dis N L 10
  write $0200 A9 41 8D 10 80
  asm $0200 LDA #$41
  asm $0202 STA $8010
  break $C020
  load "my firmware.bin" $C000
  save "snapshot.bin" $0000 0d32768
  serial 9600 7 even 1
Ranges: END is inclusive. L COUNT counts bytes for mem, instructions for dis.
Defaults: mem shows 128 bytes (up to $FFFF); dis shows 16 instructions.
Disassembly includes the whole instruction starting at or before END.
dis N continues after the last instruction shown (PC if none); n also works.
mem N continues after the last byte shown (PC if none); n also works.
Memory and disassembly keep separate next addresses.
The next address wraps at $FFFF. Empty/invalid requests leave it unchanged.
Serial: baud 1..4000000, data 5..8, parity none/even/odd/mark/space,
stop 1/1.5/2 (1.5 requires 5 data bits). Changes affect new frames and
persist through reset; guest firmware still programs the ACIA registers.
Inspection never clears I/O flags. Edits/load/assembly require a complete
RAM/ROM range and bypass ROM write protection. Use io for device registers.
)";
    }
}
