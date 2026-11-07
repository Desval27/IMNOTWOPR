#include "joshua/monitor.hpp"
#include <fstream>
#include <iostream>
#include <random>
#include <sstream>
#include <stdexcept>

using namespace joshua;
namespace
{
void check(bool condition, const char *message)
{
    if (!condition)
        throw std::runtime_error(message);
}
template <class F> void rejects(F function)
{
    try
    {
        function();
    }
    catch (const std::exception &)
    {
        return;
    }
    throw std::runtime_error("expected state operation to fail");
}
struct TemporaryDirectory
{
    std::filesystem::path path;
    TemporaryDirectory()
    {
        for (unsigned i = 0; i < 16; ++i)
        {
            path = std::filesystem::temp_directory_path() / ("joshua-state-" + std::to_string(std::random_device{}()));
            if (std::filesystem::create_directory(path))
                return;
        }
        throw std::runtime_error("cannot create test directory");
    }
    ~TemporaryDirectory()
    {
        std::error_code ignored;
        std::filesystem::remove_all(path, ignored);
    }
};

void roundTrip(const std::filesystem::path &directory)
{
    Config config;
    config.consoleNewline = ConsoleNewline::automatic;
    Machine machine(config);
    auto via = machine.via;
    auto acia = machine.acia;
    auto checkpoint = directory / "checkpoint.state";
    auto actual = directory / "actual.state";
    auto expected = directory / "expected.state";
    machine.bus.patch(0x200, std::array<Byte, 6>{0xee, 0x00, 0x04, 0x4c, 0x00, 0x02});
    machine.bus.patch(0x300, std::array<Byte, 1>{0x40}); // RTI from pending NMI.
    machine.bus.patch(0xfffa, std::array<Byte, 2>{0x00, 0x03});
    machine.cpu.r = {0x200, 0x12, 0x34, 0x56, 0x98, 0x2d};
    machine.breakpoints = {{0x200, true}, {0x300, false}};
    via->setPortA(0x5a);
    via->setPortB(0xa5);
    via->write(11, 0xc0); // Continuous T1, PB7 output.
    via->write(14, 0xe0);
    via->write(4, 3);
    via->write(5, 0);
    via->write(8, 0x71);
    via->write(9, 0);
    acia->write(2, 9);
    acia->write(3, 0x1f);
    acia->write(0, 'A');
    acia->receive('a');
    for (unsigned i = 0; i < 530; ++i)
        machine.bus.idle(); // Pending output, receive-full and IRQ flags.
    acia->receive('b');
    acia->receive('c');
    machine.bus.idle(); // Partially received frame and another queued byte.
    acia->write(0, 'B');
    acia->write(0, 'C'); // Partially transmitted frame plus overwrite count.
    machine.cpu.nmi();
    std::ostringstream ignored;
    machine.consoleOutput.write(ignored, '\r'); // Preserve CR/LF folding context.
    const auto cycles = machine.bus.cycles();
    machine.saveState(checkpoint);
    check(machine.bus.cycles() == cycles, "saving advanced the bus");

    auto advance = [&] {
        std::ostringstream result;
        machine.consoleOutput.write(result, '\n');
        machine.bus.trace = [&](const BusCycle &cycle) {
            result << cycle.number << ':' << cycle.address << ':' << unsigned(cycle.data) << ':' << cycle.write << ':'
                   << cycle.sync << '\n';
        };
        for (unsigned i = 0; i < 700; ++i)
        {
            machine.cpu.step();
            result << unsigned(via->peek(0)) << ':' << unsigned(via->peek(4)) << ':' << unsigned(via->peek(13)) << ':'
                   << unsigned(acia->peek(1)) << '\n';
            if (i % 100 == 0)
                result << unsigned(acia->read(0)) << '\n';
            while (auto byte = acia->takeTransmitted())
                result << unsigned(*byte) << '\n';
        }
        machine.bus.trace = {};
        return result.str();
    };
    auto trace = advance();
    machine.saveState(expected);
    machine.reset();
    machine.bus.patch(0x200, std::array<Byte, 1>{0xdb});
    machine.bus.patch(0xfffa, std::array<Byte, 1>{0xff});
    machine.breakpoints.clear();
    machine.consoleOutput.setMode(ConsoleNewline::raw);
    acia->setPeerSettings({9600, 7, Parity::even, 2});
    unsigned callbacks = 0;
    machine.bus.trace = [&](const BusCycle &) { ++callbacks; };
    machine.loadState(checkpoint);
    check(callbacks == 0 && machine.bus.trace, "restoring touched bus callbacks");
    check(machine.bus.cycles() == cycles && machine.via == via && machine.acia == acia,
          "restoring changed time or device identity");
    machine.saveState(actual);
    check(readBinary(actual) == readBinary(checkpoint), "full state round trip differs");
    check(advance() == trace, "restored execution/device trace differs");
    machine.saveState(actual);
    check(readBinary(actual) == readBinary(expected), "continued state differs");
    machine.bus.write(0xc000, 0);
    check(machine.bus.peek(0xc000) == 0xff, "restoring lost ROM protection");

    // A late map mismatch must not commit earlier RAM/device fields.
    auto otherConfig = config;
    otherConfig.acia = 0x8020;
    Machine other(otherConfig);
    other.saveState(expected);
    rejects([&] { other.loadState(checkpoint); });
    other.saveState(actual);
    check(readBinary(actual) == readBinary(expected), "incompatible load mutated machine");
    otherConfig = config;
    otherConfig.clockHz *= 2;
    Machine otherClock(otherConfig);
    rejects([&] { otherClock.loadState(checkpoint); });
    rejects([&] { machine.loadState(directory / "missing.state"); });
    rejects([&] { machine.saveState(directory / "missing" / "state"); });
    auto saved = readBinary(checkpoint);
    rejects([&] { machine.saveState(directory); });
    check(readBinary(checkpoint) == saved, "failed save damaged checkpoint");
}

void stoppedAndWaiting(const std::filesystem::path &directory)
{
    auto file = directory / "cpu.state";
    for (Byte opcode : {0xcb, 0xdb})
    {
        Machine machine(Config{});
        machine.cpu.r.pc = 0x200;
        machine.bus.patch(0x200, std::array<Byte, 1>{opcode});
        machine.cpu.step();
        machine.saveState(file);
        machine.reset();
        machine.loadState(file);
        check(machine.cpu.waiting() == (opcode == 0xcb), "WAI state lost");
        check(machine.cpu.stopped() == (opcode == 0xdb), "STP state lost");
        check(machine.cpu.step() == (opcode == 0xcb ? 1u : 0u), "halted CPU did not resume correctly");
    }
    Config config;
    config.ram = {{0, 0x10000, {}}};
    config.rom.clear();
    config.via.reset();
    config.acia.reset();
    Machine flat(config);
    flat.bus.patch(0xffff, std::array<Byte, 1>{0x42});
    flat.saveState(file);
    flat.bus.patch(0xffff, std::array<Byte, 1>{0});
    flat.loadState(file);
    check(flat.bus.peek(0xffff) == 0x42, "flat map without peripherals did not restore");
}
} // namespace

int main()
{
    try
    {
        TemporaryDirectory directory;
        roundTrip(directory.path);
        stoppedAndWaiting(directory.path);
        std::cout << "State checks passed.\n";
    }
    catch (const std::exception &error)
    {
        std::cerr << "FAIL: " << error.what() << '\n';
        return 1;
    }
}
