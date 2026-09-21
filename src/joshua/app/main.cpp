#include "joshua/config.hpp"
#include "joshua/instruction.hpp"
#include "joshua/monitor.hpp"
#include "terminal.hpp"
#include <algorithm>
#include <chrono>
#include <csignal>
#include <fstream>
#include <iostream>
#include <thread>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

namespace {
volatile std::sig_atomic_t interrupted = 0;
void signalHandler(int) { interrupted = 1; }

void drain(joshua::Machine& machine) {
    if (machine.acia) {
        bool wrote = false;
        while (auto value = machine.acia->takeTransmitted()) { std::cout.put(static_cast<char>(*value)); wrote = true; }
        if (wrote) std::cout.flush();
    }
}
void run(joshua::Machine& machine, const joshua::Config& config, std::optional<joshua::Word>& lastBreakpoint, bool consoleInput) {
    using Clock = std::chrono::steady_clock;
    auto startTime = Clock::now();
    auto startCycle = machine.bus.cycles();
    std::optional<Terminal> terminal;
    if (consoleInput) terminal.emplace();
    std::cerr << "Running; console escape=$" << joshua::hex(config.escape, 2) << ".\n";
    if (machine.acia) std::cerr << "Console serial: " << machine.acia->peerSettings().description() << '\n';
    bool bypass = lastBreakpoint && *lastBreakpoint == machine.cpu.r.pc;
    lastBreakpoint.reset();
    std::uint64_t nextPoll = 0;
    while (!interrupted) {
        auto elapsed = machine.bus.cycles() - startCycle;
        if (machine.cpu.stopped()) { std::cerr << "\nCPU stopped (STP).\n"; break; }
        if (config.cycleLimit && elapsed >= config.cycleLimit) { std::cerr << "\nCycle limit reached.\n"; break; }
        if (!bypass) {
            auto point = machine.breakpoints.find(machine.cpu.r.pc);
            if (point != machine.breakpoints.end() && point->second) {
                lastBreakpoint = point->first;
                std::cerr << "\nBreakpoint at $" << joshua::hex(point->first) << ".\n"; break;
            }
        }
        bypass = false;
        if (elapsed >= nextPoll) {
            nextPoll = elapsed + 256;
            if (terminal) {
                bool escaped = false;
                // Bound each poll so pasted text cannot starve emulated time.
                for (unsigned i = 0; i < 64; ++i) {
                    auto value = terminal->poll();
                    if (!value) break;
                    if (*value == config.escape) { escaped = true; break; }
                    if (machine.acia) machine.acia->receive(*value);
                }
                if (escaped || terminal->eof()) { std::cerr << "\nMonitor.\n"; break; }
            }
            drain(machine);
            if (config.throttle) {
                auto target = startTime + std::chrono::nanoseconds(elapsed * 1'000'000'000ull / config.clockHz);
                // Short sleeps keep host input responsive even at low emulated clock rates.
                while (Clock::now() < target && !interrupted) {
                    auto remaining = target - Clock::now();
                    std::this_thread::sleep_for(std::min(remaining, std::chrono::duration_cast<Clock::duration>(std::chrono::milliseconds(10))));
                    if (terminal) {
                        auto value = terminal->poll();
                        if (value && *value == config.escape) { drain(machine); return; }
                        if (value && machine.acia) machine.acia->receive(*value);
                    }
                }
            }
        }
        machine.cpu.step();
    }
    drain(machine);
}
}
int main(int argc, char** argv) {
    try {
        auto config = joshua::parseArguments(argc, argv);
        if (config.help) { std::cout << joshua::usage(); return 0; }
        if (config.version) { std::cout << "joshua 0.1.0\n"; return 0; }
#ifdef _WIN32
        // Preserve guest bytes when stdout is redirected to a binary capture.
        _setmode(_fileno(stdout), _O_BINARY);
#endif
        std::signal(SIGINT, signalHandler); std::signal(SIGTERM, signalHandler);
        joshua::Machine machine(config);
        joshua::Monitor monitor(machine, std::cerr);
        std::ifstream script;
        std::istream* commands = &std::cin;
        if (!config.script.empty()) {
            script.open(config.script);
            if (!script) throw std::runtime_error("cannot open monitor script: " + config.script.string());
            commands = &script;
        }
        std::optional<joshua::Word> lastBreakpoint;
        std::cerr << "joshua 0.1.0 - type help for monitor commands.\n";
        if (config.run) run(machine, config, lastBreakpoint, config.script.empty());
        bool failed = false;
        while (!interrupted) {
            drain(machine);
            if (commands == &std::cin) std::cerr << machine.status() << "\njoshua> " << std::flush;
            std::string line;
            if (!std::getline(*commands, line)) break;
            try {
                auto action = monitor.execute(line);
                if (action == joshua::MonitorAction::quit) break;
                if (action == joshua::MonitorAction::run) run(machine, config, lastBreakpoint, config.script.empty());
            } catch (const std::exception& error) {
                std::cerr << "Error: " << error.what() << '\n';
                failed = true;
                if (commands == &script) break;
            }
        }
        drain(machine);
        return failed ? 1 : 0;
    } catch (const std::exception& error) {
        std::cerr << "joshua: " << error.what() << '\n'; return 1;
    }
}
