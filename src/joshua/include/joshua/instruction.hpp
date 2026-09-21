#pragma once
#include "joshua/memory.hpp"
#include <array>
#include <string_view>

namespace joshua {
enum class Mode { implied, accumulator, immediate, zp, zpx, zpy, absolute, absx, absy,
                  indx, indy, indirectZp, indirect, indirectX, relative, bitBranch };
struct Instruction {
    std::string_view name;
    Mode mode;
    Byte bytes;
    Byte nopCycles = 0;
};
const std::array<Instruction, 256>& instructions();
std::uint32_t number(std::string_view text, std::uint32_t maximum = 65535, int base = 16);
std::string hex(std::uint64_t value, unsigned width = 4);
std::string disassemble(const Bus& bus, Word address);
std::vector<Byte> assemble(Word address, std::string text);
}
