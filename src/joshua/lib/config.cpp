#include "joshua/config.hpp"
#include "joshua/instruction.hpp"
#include <fstream>
#include <limits>
#include <set>
#include <stdexcept>

namespace joshua {
namespace {
std::string trim(std::string s) {
    auto begin = s.find_first_not_of(" \t\r\n");
    if (begin == std::string::npos) return {};
    return s.substr(begin, s.find_last_not_of(" \t\r\n") - begin + 1);
}
struct Settings {
    Config& config;
    std::set<std::string> seen;
    void apply(const std::string& key, std::string value, const std::filesystem::path& directory = {}) {
        value = trim(value);
        if (key == "ram" || key == "rom") {
            auto& regions = key == "ram" ? config.ram : config.rom;
            if (seen.insert(key).second) regions.clear();
            if (value == "none") { regions.clear(); return; }
            auto first = value.find(':');
            auto second = first == std::string::npos ? first : value.find(':', first + 1);
            if (first == std::string::npos) throw std::runtime_error(key + " needs base:size[:image]");
            RegionConfig region{number(value.substr(0, first)),
                number(value.substr(first + 1, second == std::string::npos ? second : second - first - 1), 65536), {}};
            if (region.size == 0 || region.size > 65536 - region.base) throw std::runtime_error("invalid " + key + " range");
            if (second != std::string::npos) {
                std::string image = trim(value.substr(second + 1));
                if (image.size() >= 2 && image.front() == '"' && image.back() == '"') image = image.substr(1, image.size() - 2);
                if (image.empty()) throw std::runtime_error("empty image path");
                region.image = directory / image;
            }
            regions.push_back(region);
        } else if (key == "via" || key == "acia") {
            auto& destination = key == "via" ? config.via : config.acia;
            if (value == "none") destination.reset();
            else destination = static_cast<Word>(number(value));
        } else if (key == "clock-hz") {
            config.clockHz = number(value, 100'000'000, 10);
            if (!config.clockHz) throw std::runtime_error("clock-hz must be positive");
        } else if (key == "escape") {
            config.escape = static_cast<Byte>(number(value, 31));
            if (!config.escape || config.escape == 10 || config.escape == 13)
                throw std::runtime_error("escape must be a control byte other than NUL, LF or CR");
        } else if (key == "pc") config.pc = static_cast<Word>(number(value));
        else throw std::runtime_error("unknown profile key: " + key);
    }
};
void profile(Config& config, const std::filesystem::path& path) {
    std::ifstream in(path);
    if (!in) throw std::runtime_error("cannot open profile: " + path.string());
    Settings settings{config, {}};
    std::string line;
    unsigned lineNumber = 0;
    while (std::getline(in, line)) {
        ++lineNumber;
        line = trim(line);
        if (line.empty() || line[0] == '#' || line[0] == ';') continue;
        try {
            auto eq = line.find('=');
            if (eq == std::string::npos) throw std::runtime_error("expected key = value");
            settings.apply(trim(line.substr(0, eq)), trim(line.substr(eq + 1)), path.parent_path());
        } catch (const std::exception& error) {
            throw std::runtime_error(path.string() + ":" + std::to_string(lineNumber) + ": " + error.what());
        }
    }
    if (in.bad()) throw std::runtime_error("failed reading profile: " + path.string());
}
}
Config parseArguments(int argc, char** argv) {
    Config result;
    std::vector<std::pair<std::string, std::string>> overrides;
    std::optional<std::filesystem::path> profilePath;
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--help" || arg == "-h") result.help = true;
        else if (arg == "--version") result.version = true;
        else if (arg == "--run") result.run = true;
        else if (arg == "--unthrottled") result.throttle = false;
        else {
            static const std::set<std::string> options{"--profile", "--ram", "--rom", "--via", "--acia", "--clock-hz", "--escape", "--pc", "--script", "--cycles"};
            if (!options.contains(arg)) throw std::runtime_error("unknown option: " + arg);
            if (++i == argc) throw std::runtime_error("missing value for " + arg);
            std::string value = argv[i];
            if (arg == "--profile") {
                if (profilePath) throw std::runtime_error("only one --profile is allowed");
                profilePath = value;
            } else if (arg == "--script") result.script = value;
            else if (arg == "--cycles") {
                result.cycleLimit = number(value, std::numeric_limits<std::uint32_t>::max(), 10);
                if (!result.cycleLimit) throw std::runtime_error("--cycles must be positive");
            } else overrides.emplace_back(arg.substr(2), value);
        }
    }
    if (result.help || result.version) return result;
    if (profilePath) profile(result, *profilePath);
    Settings settings{result, {}};
    for (const auto& [key, value] : overrides) settings.apply(key, value);
    return result;
}
std::vector<Byte> readBinary(const std::filesystem::path& path) {
    std::ifstream in(path, std::ios::binary | std::ios::ate);
    if (!in) throw std::runtime_error("cannot open binary: " + path.string());
    auto size = in.tellg();
    if (size < 0 || size > 65536) throw std::runtime_error("binary must be at most 65536 bytes");
    std::vector<Byte> bytes(static_cast<std::size_t>(size));
    in.seekg(0);
    if (!bytes.empty() && !in.read(reinterpret_cast<char*>(bytes.data()), static_cast<std::streamsize>(bytes.size())))
        throw std::runtime_error("failed reading binary: " + path.string());
    return bytes;
}
std::string usage() {
    return R"(joshua 0.1.0 - IMNOTWOPR W65C02 development machine
Usage: joshua [options]
  --profile FILE           Read a key = value machine profile
  --ram BASE:SIZE[:FILE]    Replace RAM mappings; repeat to add regions
  --rom BASE:SIZE[:FILE]    Replace ROM mappings; repeat to add regions
  --via BASE               Map 16 VIA registers
  --acia BASE              Map 4 ACIA registers
                           Use 'none' to omit RAM, ROM, VIA or ACIA
  --clock-hz HZ            CPU clock in decimal (default 1000000)
  --pc ADDRESS             Override PC after reset
  --escape BYTE            Console escape byte (default $1D, Ctrl-])
  --run                    Start in serial console mode
  --unthrottled            Run as fast as the host allows
  --cycles COUNT           Stop each run after COUNT cycles (decimal)
  --script FILE            Read monitor commands from FILE
  --help, --version        Show help or version
Addresses, sizes and bytes are hexadecimal; $/0x, 0d, 0o and 0b
prefixes select hexadecimal, decimal, octal and binary explicitly.
CLI mappings override profile mappings of the same type, regardless of order.
Default: RAM $0000:$8000, ROM $C000:$4000, VIA $8000, ACIA $8010.
)";
}
}
