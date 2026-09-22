#pragma once
#include "joshua/machine.hpp"
#include <iosfwd>
#include <optional>

namespace joshua
{
    enum class MonitorAction
    {
        prompt,
        run,
        quit
    };
    class Monitor
    {
    public:
        Monitor(Machine &machine, std::ostream &out) : machine_(machine), out_(out) {}
        MonitorAction execute(const std::string &line);
        static std::string help();

    private:
        Machine &machine_;
        std::ostream &out_;
        std::optional<Word> nextDisassembly_;
        std::optional<Word> nextMemory_;
    };
}
