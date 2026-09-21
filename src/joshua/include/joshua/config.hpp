#pragma once
#include "joshua/memory.hpp"
#include <filesystem>
#include <optional>

namespace joshua {
struct RegionConfig {
    std::uint32_t base, size;
    std::filesystem::path image;
};
struct Config {
    std::vector<RegionConfig> ram{{0x0000, 0x8000, {}}};
    std::vector<RegionConfig> rom{{0xc000, 0x4000, {}}};
    std::optional<Word> via = 0x8000, acia = 0x8010, pc;
    std::uint32_t clockHz = 1'000'000;
    Byte escape = 0x1d;
    std::uint64_t cycleLimit = 0;
    bool run = false, throttle = true, help = false, version = false;
    std::filesystem::path script;
};
Config parseArguments(int argc, char** argv);
std::string usage();
std::vector<Byte> readBinary(const std::filesystem::path& path);
}
