#include "joshua/machine.hpp"
#include "joshua/instruction.hpp"
#include <fstream>
#include <stdexcept>

namespace joshua {
Machine::Machine(const Config& config) : cpu(bus), consoleOutput(config.consoleNewline) {
    auto add = [&](const auto& regions, bool rom) {
        unsigned index = 0;
        for (const auto& region : regions) {
            auto memory = std::make_shared<Memory>(region.size, rom);
            if (!region.image.empty()) {
                auto bytes = readBinary(region.image);
                if (bytes.size() > region.size) throw std::runtime_error("image exceeds mapping: " + region.image.string());
                for (std::size_t i = 0; i < bytes.size(); ++i) memory->patch(static_cast<Word>(i), bytes[i]);
            }
            bus.map({std::string(rom ? "ROM" : "RAM") + std::to_string(index++), region.base, region.size, memory});
        }
    };
    add(config.ram, false); add(config.rom, true);
    if (config.via) { via = std::make_shared<Via>(); bus.map({"VIA", *config.via, 16, via}); }
    if (config.acia) { acia = std::make_shared<Acia>(config.clockHz, config.serial); bus.map({"ACIA", *config.acia, 4, acia}); }
    reset();
    if (config.pc) cpu.r.pc = *config.pc;
}
void Machine::reset() { bus.resetDevices(); cpu.reset(); }
void Machine::load(Word address, const std::filesystem::path& file) { bus.patch(address, readBinary(file)); }
void Machine::save(Word address, std::uint32_t size, const std::filesystem::path& file) const {
    if (size > 65536u - address) throw std::runtime_error("save range exceeds $FFFF");
    std::vector<Byte> data(size);
    for (std::uint32_t i = 0; i < size; ++i) data[i] = bus.peek(static_cast<Word>(address + i));
    std::ofstream out(file, std::ios::binary | std::ios::trunc);
    if (!out) throw std::runtime_error("cannot create binary: " + file.string());
    out.write(reinterpret_cast<const char*>(data.data()), static_cast<std::streamsize>(data.size()));
    out.close();
    if (!out) throw std::runtime_error("failed writing binary: " + file.string());
}
std::string Machine::status() const {
    const auto& r = cpu.r;
    return "PC=" + hex(r.pc) + " A=" + hex(r.a, 2) + " X=" + hex(r.x, 2) + " Y=" + hex(r.y, 2) +
        " SP=" + hex(r.sp, 2) + " P=" + hex(r.p, 2) + " [NV-BDIZC] cycles=" + std::to_string(bus.cycles()) +
        (cpu.stopped() ? " STP" : cpu.waiting() ? " WAI" : "") + "  " + disassemble(bus, r.pc);
}
}
