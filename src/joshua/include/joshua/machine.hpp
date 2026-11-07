#pragma once
#include "joshua/config.hpp"
#include "joshua/cpu.hpp"
#include "joshua/devices.hpp"
#include <map>

namespace joshua
{
    class Machine
    {
        friend class StateCodec;
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
        // Versioned full-machine snapshots; loading requires the same map and clock.
        void saveState(const std::filesystem::path &file) const;
        void loadState(const std::filesystem::path &file);
        std::string status() const;

    private:
        std::uint32_t clockHz_;
    };
}
