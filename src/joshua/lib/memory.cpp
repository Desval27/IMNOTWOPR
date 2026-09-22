#include "joshua/memory.hpp"
#include <stdexcept>
#include <utility>

namespace joshua
{
    void Device::patch(Word, Byte) { throw std::runtime_error("device is not patchable memory"); }
    Memory::Memory(std::uint32_t size, bool readOnly)
        : bytes_(size, readOnly ? 0xff : 0), readOnly_(readOnly) {}
    Byte Memory::peek(Word offset) const { return bytes_.at(offset); }
    void Memory::write(Word offset, Byte value)
    {
        if (!readOnly_)
            bytes_.at(offset) = value;
    }
    void Memory::patch(Word offset, Byte value) { bytes_.at(offset) = value; }

    void Bus::map(Mapping mapping)
    {
        if (!mapping.device || mapping.size == 0 || mapping.base >= 65536 ||
            mapping.size > 65536 - mapping.base)
            throw std::runtime_error("invalid memory mapping: " + mapping.name);
        for (const auto &m : mappings_)
            if (mapping.base < m.base + m.size && m.base < mapping.base + mapping.size)
                throw std::runtime_error("overlapping mappings: " + mapping.name + " and " + m.name);
        mappings_.push_back(std::move(mapping));
    }
    const Mapping *Bus::locate(Word address) const
    {
        for (const auto &m : mappings_)
            if (address >= m.base && address < m.base + m.size)
                return &m;
        return nullptr;
    }
    void Bus::tick()
    {
        ++cycles_;
        for (const auto &m : mappings_)
            m.device->tick();
    }
    Byte Bus::read(Word address, bool sync)
    {
        auto m = locate(address);
        Byte value = m ? m->device->read(static_cast<Word>(address - m->base)) : 0xff;
        tick();
        if (trace)
            trace({cycles_, address, value, false, sync});
        return value;
    }
    void Bus::write(Word address, Byte value)
    {
        if (auto m = locate(address))
            m->device->write(static_cast<Word>(address - m->base), value);
        tick();
        if (trace)
            trace({cycles_, address, value, true, false});
    }
    Byte Bus::peek(Word address) const
    {
        auto m = locate(address);
        return m ? m->device->peek(static_cast<Word>(address - m->base)) : 0xff;
    }
    void Bus::patch(std::uint32_t address, std::span<const Byte> bytes)
    {
        if (address > 65535 || bytes.size() > 65536 - address)
            throw std::runtime_error("memory range exceeds $FFFF");
        for (std::size_t i = 0; i < bytes.size(); ++i)
        {
            auto m = locate(static_cast<Word>(address + i));
            if (!m || !m->device->patchable())
                throw std::runtime_error("entire range must be mapped RAM or ROM");
        }
        for (std::size_t i = 0; i < bytes.size(); ++i)
        {
            auto m = locate(static_cast<Word>(address + i));
            m->device->patch(static_cast<Word>(address + i - m->base), bytes[i]);
        }
    }
    void Bus::idle() { tick(); }
    void Bus::resetDevices()
    {
        for (const auto &m : mappings_)
            m.device->reset();
    }
    bool Bus::irq() const
    {
        for (const auto &m : mappings_)
            if (m.device->irq())
                return true;
        return false;
    }
}
