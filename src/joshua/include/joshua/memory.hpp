#pragma once
#include <cstdint>
#include <functional>
#include <memory>
#include <span>
#include <string>
#include <vector>

namespace joshua {
using Byte = std::uint8_t;
using Word = std::uint16_t;

class Device {
public:
    virtual ~Device() = default;
    virtual Byte peek(Word offset) const = 0;
    virtual Byte read(Word offset) { return peek(offset); }
    virtual void write(Word offset, Byte value) = 0;
    virtual bool patchable() const { return false; }
    virtual void patch(Word, Byte);
    virtual void tick() {}
    virtual void reset() {}
    virtual bool irq() const { return false; }
};

class Memory final : public Device {
public:
    Memory(std::uint32_t size, bool readOnly);
    Byte peek(Word offset) const override;
    void write(Word offset, Byte value) override;
    bool patchable() const override { return true; }
    void patch(Word offset, Byte value) override;
private:
    std::vector<Byte> bytes_;
    bool readOnly_;
};

struct Mapping {
    std::string name;
    std::uint32_t base, size;
    std::shared_ptr<Device> device;
};

struct BusCycle {
    std::uint64_t number;
    Word address;
    Byte data;
    bool write, sync;
};

class Bus {
public:
    void map(Mapping mapping);
    Byte read(Word address, bool sync = false);
    void write(Word address, Byte value);
    Byte peek(Word address) const;
    // Debugger edits bypass ROM protection, never invoke device registers.
    void patch(std::uint32_t address, std::span<const Byte> bytes);
    void idle();
    void resetDevices();
    bool irq() const;
    const std::vector<Mapping>& mappings() const { return mappings_; }
    std::uint64_t cycles() const { return cycles_; }
    std::function<void(const BusCycle&)> trace;
private:
    const Mapping* locate(Word address) const;
    void tick();
    std::vector<Mapping> mappings_;
    std::uint64_t cycles_ = 0;
};
}
