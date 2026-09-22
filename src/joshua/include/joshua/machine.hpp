#pragma once
#include "joshua/config.hpp"
#include "joshua/cpu.hpp"
#include "joshua/devices.hpp"
#include <map>

namespace joshua
{
    class Machine
    {
    public:
        explicit Machine(const Config &config);
        Bus bus;
        Cpu cpu;
        std::shared_ptr<Via> via;
        std::shared_ptr<Acia> acia;
        ConsoleOutput consoleOutput;
        std::map<Word, bool> breakpoints;
        void reset();
        void load(Word address, const std::filesystem::path &file);
        void save(Word address, std::uint32_t size, const std::filesystem::path &file) const;
        std::string status() const;
    };
}
