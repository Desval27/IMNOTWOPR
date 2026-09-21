#include "joshua/monitor.hpp"
#include "joshua/instruction.hpp"
#include <algorithm>
#include <iostream>
#include <sstream>
#include <stdexcept>

using namespace joshua;
namespace {
void check(bool condition, const char* message) { if (!condition) throw std::runtime_error(message); }
template<class Function> void rejects(Function function) {
    bool rejected = false;
    try { function(); } catch (const std::exception&) { rejected = true; }
    check(rejected, "expected rejection");
}
struct Fixture {
    Bus bus;
    std::shared_ptr<Memory> ram = std::make_shared<Memory>(65536, false);
    Cpu cpu{bus};
    Fixture() { bus.map({"RAM", 0, 65536, ram}); cpu.r.pc = 0x200; }
    void code(std::initializer_list<Byte> bytes) { bus.patch(cpu.r.pc, std::span(bytes)); }
};
void cpuTests() {
    Fixture f;
    f.bus.patch(0xfffc, std::array<Byte, 2>{0x00, 0x20});
    f.cpu.reset(); check(f.cpu.r.pc == 0x2000 && f.bus.cycles() == 7, "reset vector and cycles");
    f.cpu.r.pc = 0x200; f.code({0xa9, 0x42, 0x8d, 0x00, 0x30});
    check(f.cpu.step() == 2 && f.cpu.r.a == 0x42, "LDA immediate");
    check(f.cpu.step() == 4 && f.bus.peek(0x3000) == 0x42, "STA absolute");
    f.cpu.r.pc = 0x200; f.code({0xbd, 0xff, 0x30}); f.cpu.r.x = 1;
    f.ram->patch(0x3100, 0x99); std::vector<BusCycle> trace;
    f.bus.trace = [&](auto c) { trace.push_back(c); };
    check(f.cpu.step() == 5 && f.cpu.r.a == 0x99, "page crossing read");
    check(trace[3].address == 0x202 && trace[4].address == 0x3100, "CMOS page crossing dummy read");
    trace.clear(); f.cpu.r.pc = 0x200; f.code({0xee, 0x00, 0x30});
    check(f.cpu.step() == 6 && f.bus.peek(0x3000) == 0x43, "INC timing");
    check(!trace[3].write && !trace[4].write && trace[5].write, "CMOS RMW reads twice, writes once");
    f.bus.trace = {};
    f.cpu.r.pc = 0x200; f.code({0x6c, 0xff, 0x30});
    f.ram->patch(0x30ff, 0x34); f.ram->patch(0x3100, 0x12);
    check(f.cpu.step() == 6 && f.cpu.r.pc == 0x1234, "CMOS indirect jump crosses page");
    f.cpu.r.pc = 0x200; f.code({0x69, 0x55}); f.cpu.r.a = 0x45; f.cpu.r.p = 0x28;
    check(f.cpu.step() == 3 && f.cpu.r.a == 0 && (f.cpu.r.p & 3) == 3, "decimal ADC");
    f.cpu.r.pc = 0x200; f.code({0xe9, 0x01}); f.cpu.r.a = 0x00; f.cpu.r.p = 0x29;
    check(f.cpu.step() == 3 && f.cpu.r.a == 0x99 && !(f.cpu.r.p & 1), "decimal SBC");
    f.cpu.r.pc = 0x200; f.code({0x0f, 0x10, 0x02}); f.ram->patch(0x10, 1);
    check(f.cpu.step() == 5 && f.cpu.r.pc == 0x203, "bit branch not taken");
    f.cpu.r.pc = 0x200; f.ram->patch(0x10, 0);
    check(f.cpu.step() == 6 && f.cpu.r.pc == 0x205, "bit branch taken");
    f.cpu.r.pc = 0x200; f.code({0xcb, 0xea});
    check(f.cpu.step() == 3 && f.cpu.waiting(), "WAI entry");
    check(f.cpu.step() == 1 && f.cpu.r.pc == 0x201, "WAI idle");
    f.bus.patch(0xfffa, std::array<Byte, 2>{0x00, 0x40}); f.cpu.nmi();
    check(f.cpu.step() == 7 && f.cpu.r.pc == 0x4000 && !(f.cpu.r.p & 8), "NMI wakes WAI and clears decimal");
    f.cpu.r.pc = 0x200; f.code({0xdb});
    check(f.cpu.step() == 3 && f.cpu.stopped() && f.cpu.step() == 0, "STP stops");
    f.cpu.reset(); check(!f.cpu.stopped(), "reset releases STP");
}
void assemblerTests() {
    Fixture f;
    for (unsigned opcode = 0; opcode < 256; ++opcode) {
        f.bus.patch(0x200, std::array<Byte, 3>{static_cast<Byte>(opcode), 0x12, 0x03});
        auto text = disassemble(f.bus, 0x200);
        auto bytes = assemble(0x200, text);
        check(bytes[0] == opcode, "opcode assembly/disassembly round trip");
        for (std::size_t i = 1; i < bytes.size(); ++i) check(bytes[i] == f.bus.peek(static_cast<Word>(0x200 + i)), "operand round trip");
    }
    rejects([] { assemble(0x200, "BRA $0400"); });
    rejects([] { assemble(0x200, "LDA #$100"); });
    check(assemble(0x200, "LDA $0012")[0] == 0xad, "force absolute addressing");
    check(number("0d10") == 10 && number("0o10") == 8 && number("0b10") == 2, "number prefixes");
    check(number("$10", 65535, 10) == 16, "dollar prefix overrides decimal default");
    rejects([] { number("0o9"); }); rejects([] { number("10000"); });
}
void busAndDeviceTests() {
    Config config;
    Machine m(config);
    m.bus.patch(0xc000, std::array<Byte, 1>{0x55}); m.bus.write(0xc000, 0xaa);
    check(m.bus.peek(0xc000) == 0x55 && m.bus.peek(0x9000) == 0xff, "ROM protection and unmapped reads");
    rejects([&] { m.bus.map({"bad", 0, 1, std::make_shared<Memory>(1, false)}); });
    rejects([&] { m.bus.patch(0x7fff, std::array<Byte, 2>{1, 2}); });
    check(m.bus.peek(0x7fff) == 0, "failed patch must be atomic");
    m.bus.write(0x800e, 0xc0); m.bus.write(0x8004, 1); m.bus.write(0x8005, 0);
    check(!m.via->irq(), "timer not expired on write");
    m.bus.idle(); check(!m.via->irq(), "timer decrement");
    m.bus.idle(); check(m.via->irq(), "timer underflow IRQ");
    auto cycles = m.bus.cycles(); m.bus.peek(0x8004);
    check(m.via->irq() && cycles == m.bus.cycles(), "peek leaves clock and IRQ unchanged");
    m.bus.read(0x8004); check(!m.via->irq(), "timer read acknowledges IRQ");
    for (unsigned i = 0; i < 12; ++i) m.bus.idle();
    check(!m.via->irq(), "one-shot timer does not retrigger on reload");
    m.bus.write(0x800b, 0xc0); m.bus.write(0x8005, 0);
    m.bus.idle(); m.bus.idle(); check(m.via->irq(), "free-run first timeout");
    m.bus.read(0x8004); m.bus.idle(); m.bus.idle();
    check(m.via->irq(), "free-run retriggers at latch plus two cycles");
    m.bus.write(0x8013, 0x1f); m.bus.write(0x8012, 0x09);
    m.acia->receive('A');
    for (unsigned i = 0; i < 521; ++i) m.bus.idle();
    check((m.bus.peek(0x8011) & 0x88) == 0x88, "ACIA receive IRQ after frame");
    check(m.bus.peek(0x8010) == 'A' && m.acia->irq(), "ACIA peek does not consume byte");
    check(m.bus.read(0x8011) & 0x80, "ACIA status reports interrupt");
    check(!m.acia->irq(), "ACIA status read acknowledges IRQ");
    check(m.bus.read(0x8010) == 'A' && !(m.bus.peek(0x8011) & 8), "ACIA data consumption");
    m.bus.write(0x8010, 'B');
    check(m.bus.peek(0x8011) & 0x10, "W65C51N TDRE always set");
    check(!m.acia->takeTransmitted(), "serial output waits for frame");
    for (unsigned i = 0; i < 521; ++i) m.bus.idle();
    check(m.acia->takeTransmitted() == 'B', "serial output frame completion");
    m.bus.write(0x8010, 'C'); m.bus.write(0x8010, 'D');
    check(m.acia->overwrittenTransmits() == 1, "ACIA premature transmit overwrite");
}
void monitorTests() {
    Machine m(Config{}); std::ostringstream output; Monitor monitor(m, output);
    monitor.execute("asm 200 LDA #$42"); monitor.execute("regs pc 200"); monitor.execute("step");
    check(m.cpu.r.a == 0x42, "monitor assembly and step");
    rejects([&] { monitor.execute("write 300 01 100"); }); check(m.bus.peek(0x300) == 0, "invalid write is atomic");
    monitor.execute("break 200"); monitor.execute("break disable 200"); monitor.execute("break move 200 300");
    check(!m.breakpoints.at(0x300), "breakpoint move preserves state");
    monitor.execute("break enable 300"); check(m.breakpoints.at(0x300), "breakpoint enable");
    monitor.execute("break delete 300"); check(m.breakpoints.empty(), "breakpoint deletion");
    check(monitor.execute("run 200") == MonitorAction::run, "run action");
    rejects([&] { monitor.execute("save \"unterminated 0 10"); });

    auto capture = [&](const std::string& command) {
        output.str(""); output.clear(); monitor.execute(command); return output.str();
    };
    auto lines = [&](const std::string& command) {
        auto text = capture(command); return std::count(text.begin(), text.end(), '\n');
    };
    m.cpu.r.pc = 0x300;
    check(capture("mem N L 1").starts_with("0300  "), "initial memory N uses PC");
    check(capture("dis N L 1").starts_with("0300  "), "initial N uses PC");
    check(capture("mem 300 3FF") == capture("m 300 L 100"), "inclusive memory range equals byte count");
    check(lines("mem 300 3FF") == 16, "memory range has 256 bytes");
    check(capture("mem 300 300") == capture("mem 300 l 1"), "single-byte inclusive range");
    check(capture("mem 300") == capture("mem 300 L 80"), "default memory count");
    check(capture("mem FFFF") == capture("mem FFFF FFFF"), "default memory clips at FFFF");
    check(capture("mem 300 L 0").empty(), "zero memory count");
    check(capture("mem 300 L 0d16") == capture("mem 300 30F"), "explicit decimal count");
    check(lines("mem 0 FFFF") == 4096, "full address space memory range");
    check(capture("mem N L 1").starts_with("0000  "), "memory continuation wraps after full range");
    capture("mem 300 30A");
    check(capture("m n l 2").starts_with("030B  "), "memory N follows partial row and supports aliases");
    check(capture("mem N 30F").starts_with("030D  "), "memory N supports inclusive end");
    auto nextMemory = capture("mem N");
    check(nextMemory.starts_with("0310  ") && std::count(nextMemory.begin(), nextMemory.end(), '\n') == 8,
          "memory N defaults to 128 bytes");
    check(capture("mem N L 1").starts_with("0390  "), "default memory continuation updates next address");
    capture("mem 400 L 0");
    capture("dis 500 L 1");
    rejects([&] { monitor.execute("mem N 100"); });
    rejects([&] { monitor.execute("mem N L"); });
    rejects([&] { monitor.execute("mem N L 10000"); });
    check(capture("mem N L 1").starts_with("0391  "), "empty, invalid and disassembly requests preserve memory continuation");
    capture("mem FFFD L 1");
    check(capture("mem N").starts_with("FFFE  "), "memory N clips default at FFFF");
    check(capture("mem N L 1").starts_with("0000  "), "memory N wraps after clipped default");

    monitor.execute("write 300 A9 42 8D 00 04 EA");
    capture("dis 300 L 1");
    check(capture("dis N L 1").starts_with("0302  "), "N follows two-byte instruction");
    check(capture("d n 305").starts_with("0305  "), "lowercase N follows three-byte instruction with end address");
    capture("dis 300 303");
    auto continued = capture("dis N");
    check(continued.starts_with("0305  ") && std::count(continued.begin(), continued.end(), '\n') == 16,
          "N uses complete final instruction and default count");
    capture("dis 300 L 1");
    capture("mem 400 L 1");
    capture("dis 400 L 0");
    rejects([&] { monitor.execute("dis N 100"); });
    check(capture("dis N L 1").starts_with("0302  "), "empty, unrelated and invalid requests preserve continuation");
    capture("dis");
    check(capture("dis N L 1").starts_with("0313  "), "dis without address updates continuation");
    check(lines("dis 300 305") == 3, "range covers mixed-length instructions");
    check(capture("dis 300 302") == capture("d 300 l 2"), "inclusive final instruction start");
    check(capture("dis 300 303") == capture("dis 300 L 2"), "partial final instruction shown whole");
    check(capture("dis 300 300") == capture("dis 300 L 1"), "single-address disassembly");
    check(lines("dis 300") == 16, "default disassembly count");
    m.cpu.r.pc = 0x300;
    check(capture("dis") == capture("dis 300"), "default disassembly address is PC");
    check(capture("dis 300 L 0").empty(), "zero instruction count");
    monitor.execute("write FFFE EA EA");
    check(lines("dis FFFE FFFF") == 2, "ending at FFFF does not wrap");
    check(capture("dis N L 1").starts_with("0000  "), "N wraps after FFFF");
    monitor.execute("write FFFF A9");
    check(lines("dis FFFF FFFF") == 1, "multi-byte final instruction does not wrap range");
    check(capture("dis N L 1").starts_with("0001  "), "N wraps after multi-byte instruction at FFFF");
    for (const auto& command : {"mem", "mem 300 2FF", "dis 300 2FF", "mem 300 L", "dis 300 L",
                               "mem 300 X 2", "dis 300 X 2", "mem 300 301 302", "dis 300 301 302",
                               "mem FFFF L 2", "mem 300 10000", "dis 300 10000",
                               "mem 300 L 10001", "dis 300 L 10001"})
        rejects([&] { monitor.execute(command); });
}
}
int main() {
    try { cpuTests(); assemblerTests(); busAndDeviceTests(); monitorTests(); std::cout << "All checks passed.\n"; }
    catch (const std::exception& error) { std::cerr << "FAIL: " << error.what() << '\n'; return 1; }
}
