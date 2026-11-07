#include "joshua/machine.hpp"
#include <algorithm>
#include <concepts>
#include <fstream>
#include <random>
#include <stdexcept>
#include <tuple>
#include <type_traits>
#include <utility>

namespace joshua
{
namespace
{
constexpr std::array<Byte, 8> magic{'J', 'O', 'S', 'H', 'U', 'A', '\r', '\n'};
constexpr std::uint32_t version = 1;
constexpr std::size_t maxPayload = 16 * 1024 * 1024;

// Explicit little-endian fields, never object representations or host pointers.
struct Writer
{
    std::vector<Byte> data;
    template <std::unsigned_integral T> void operator()(T value)
    {
        if (data.size() > maxPayload - sizeof(T))
            throw std::runtime_error("state exceeds 16 MiB limit");
        for (std::size_t i = 0; i < sizeof(T); ++i)
            data.push_back(static_cast<Byte>(value >> (8 * i)));
    }
    void operator()(bool value)
    {
        (*this)(static_cast<Byte>(value));
    }
    template <class T> void expect(T value)
    {
        (*this)(value);
    }
    void queue(const std::deque<Byte> &bytes)
    {
        if (bytes.size() > maxPayload)
            throw std::runtime_error("serial queue exceeds state size limit");
        (*this)(static_cast<std::uint32_t>(bytes.size()));
        for (auto byte : bytes)
            (*this)(byte);
    }
};

struct Reader
{
    std::span<const Byte> data;
    template <std::unsigned_integral T> void operator()(T &value)
    {
        if (data.size() < sizeof(T))
            throw std::runtime_error("truncated state file");
        value = 0;
        for (std::size_t i = 0; i < sizeof(T); ++i)
            value |= static_cast<T>(data[i]) << (8 * i);
        data = data.subspan(sizeof(T));
    }
    void operator()(bool &value)
    {
        Byte raw;
        (*this)(raw);
        if (raw > 1)
            throw std::runtime_error("invalid state boolean");
        value = raw != 0;
    }
    template <class T> void expect(T expected)
    {
        T actual;
        (*this)(actual);
        if (actual != expected)
            throw std::runtime_error("state memory map or clock does not match this machine");
    }
    void queue(std::deque<Byte> &bytes)
    {
        std::uint32_t count;
        (*this)(count);
        if (count > data.size())
            throw std::runtime_error("invalid state serial queue length");
        bytes.assign(data.begin(), data.begin() + count);
        data = data.subspan(count);
    }
};

std::uint32_t checksum(std::span<const Byte> bytes)
{
    std::uint32_t crc = 0xffffffff;
    for (Byte byte : bytes)
    {
        crc ^= byte;
        for (unsigned bit = 0; bit < 8; ++bit)
            crc = (crc >> 1) ^ ((crc & 1) ? 0xedb88320u : 0);
    }
    return ~crc;
}
} // namespace

// The codec is the only friend with access to private emulation latches. Both
// directions share the field list so new state cannot be restored via I/O writes.
class StateCodec
{
    static auto aciaMembers(Acia &a)
    {
        return std::tie(a.clockHz_, a.peer_, a.command_, a.control_, a.received_, a.transmit_, a.incoming_, a.full_,
                        a.overrun_, a.interrupt_, a.txRemaining_, a.rxRemaining_, a.overwritten_, a.input_, a.output_);
    }
    template <class Archive, class C> static void cpu(Archive &ar, C &c)
    {
        ar(c.r.pc);
        ar(c.r.a);
        ar(c.r.x);
        ar(c.r.y);
        ar(c.r.sp);
        ar(c.r.p);
        ar(c.waiting_);
        ar(c.stopped_);
        ar(c.nmiPending_);
    }
    template <class Archive> static void via(Archive &ar, Via &v)
    {
        for (auto &byte : v.registers_)
            ar(byte);
        ar(v.t1_);
        ar(v.t2_);
        ar(v.latch1_);
        ar(v.latch2Low_);
        ar(v.ifr_);
        ar(v.ier_);
        ar(v.inputA_);
        ar(v.inputB_);
        ar(v.armed1_);
        ar(v.armed2_);
        ar(v.pb7_);
        ar(v.delay1_);
        ar(v.delay2_);
        ar(v.reload1_);
    }
    template <class Archive> static void acia(Archive &ar, Acia &a)
    {
        ar.expect(a.clockHz_);
        ar(a.peer_.baud);
        // Use fixed widths even on hosts with a different unsigned/enum size.
        auto bits = static_cast<std::uint32_t>(a.peer_.dataBits);
        auto parity = static_cast<Byte>(a.peer_.parity);
        auto stop = static_cast<std::uint32_t>(a.peer_.stopHalfBits);
        ar(bits);
        ar(parity);
        ar(stop);
        if constexpr (std::same_as<Archive, Reader>)
        {
            a.peer_ = {a.peer_.baud, bits, static_cast<Parity>(parity), stop};
            a.peer_.validate();
        }
        ar(a.command_);
        ar(a.control_);
        ar(a.received_);
        ar(a.transmit_);
        ar(a.incoming_);
        ar(a.full_);
        ar(a.overrun_);
        ar(a.interrupt_);
        ar(a.txRemaining_);
        ar(a.rxRemaining_);
        ar(a.overwritten_);
        ar.queue(a.input_);
        ar.queue(a.output_);
    }
    static Byte kind(const Mapping &mapping)
    {
        if (auto memory = dynamic_cast<Memory *>(mapping.device.get()))
            return memory->readOnly_ ? 1 : 0;
        if (dynamic_cast<Via *>(mapping.device.get()))
            return 2;
        if (dynamic_cast<Acia *>(mapping.device.get()))
            return 3;
        throw std::runtime_error("unsupported device in state file: " + mapping.name);
    }
    template <class Archive, class M> static void fields(Archive &ar, M &m)
    {
        ar.expect(m.clockHz_);
        ar.expect(static_cast<std::uint32_t>(m.bus.mappings_.size()));
        for (const auto &mapping : m.bus.mappings_)
        {
            ar.expect(mapping.base);
            ar.expect(mapping.size);
            ar.expect(kind(mapping));
            if (auto memory = dynamic_cast<Memory *>(mapping.device.get()))
                for (auto &byte : memory->bytes_)
                    ar(byte);
            else if (auto v = dynamic_cast<Via *>(mapping.device.get()))
                via(ar, *v);
            else if (auto a = dynamic_cast<Acia *>(mapping.device.get()))
                acia(ar, *a);
        }
        ar(m.bus.cycles_);
        cpu(ar, m.cpu);
        auto mode = static_cast<Byte>(m.consoleOutput.mode_);
        ar(mode);
        if constexpr (std::same_as<Archive, Reader>)
        {
            if (mode > static_cast<Byte>(ConsoleNewline::automatic))
                throw std::runtime_error("invalid state console newline mode");
            m.consoleOutput.mode_ = static_cast<ConsoleNewline>(mode);
        }
        ar(m.consoleOutput.previousCr_);
        auto count = static_cast<std::uint32_t>(m.breakpoints.size());
        ar(count);
        if constexpr (std::same_as<Archive, Reader>)
        {
            if (count > 65536)
                throw std::runtime_error("invalid state breakpoint count");
            m.breakpoints.clear();
            for (std::uint32_t i = 0; i < count; ++i)
            {
                Word address;
                bool enabled;
                ar(address);
                ar(enabled);
                if (!m.breakpoints.emplace(address, enabled).second)
                    throw std::runtime_error("duplicate state breakpoint");
            }
        }
        else
            for (auto [address, enabled] : m.breakpoints)
            {
                ar(address);
                ar(enabled);
            }
    }

  public:
    static std::vector<Byte> encode(const Machine &machine)
    {
        Writer writer;
        fields(writer, machine);
        return std::move(writer.data);
    }
    static void decode(Machine &machine, std::span<const Byte> data)
    {
        // Clone devices before parsing. A malformed or incompatible snapshot must
        // leave every live byte, latch and host callback unchanged.
        Config empty;
        empty.ram.clear();
        empty.rom.clear();
        empty.via.reset();
        empty.acia.reset();
        empty.clockHz = machine.clockHz_;
        Machine staged(empty);
        staged.bus.mappings_ = machine.bus.mappings_;
        for (auto &mapping : staged.bus.mappings_)
        {
            if (auto memory = dynamic_cast<Memory *>(mapping.device.get()))
                mapping.device = std::make_shared<Memory>(*memory);
            else if (auto v = dynamic_cast<Via *>(mapping.device.get()))
                mapping.device = std::make_shared<Via>(*v);
            else if (auto a = dynamic_cast<Acia *>(mapping.device.get()))
                mapping.device = std::make_shared<Acia>(*a);
            else
                kind(mapping); // Report unsupported devices before decoding.
        }
        Reader reader{data};
        fields(reader, staged);
        if (!reader.data.empty())
            throw std::runtime_error("unexpected trailing state data");

        // No-throw commit preserves device identities and the CPU's bus reference.
        static_assert(std::is_nothrow_swappable_v<Memory> && std::is_nothrow_swappable_v<Via>);
        for (std::size_t i = 0; i < machine.bus.mappings_.size(); ++i)
        {
            auto live = machine.bus.mappings_[i].device.get();
            auto saved = staged.bus.mappings_[i].device.get();
            if (auto memory = dynamic_cast<Memory *>(live))
                std::swap(*memory, *static_cast<Memory *>(saved));
            else if (auto v = dynamic_cast<Via *>(live))
                std::swap(*v, *static_cast<Via *>(saved));
            else if (auto a = dynamic_cast<Acia *>(live))
            {
                // deque's move construction may allocate; swap its buffers directly.
                auto liveMembers = aciaMembers(*a);
                auto savedMembers = aciaMembers(*static_cast<Acia *>(saved));
                static_assert(noexcept(liveMembers.swap(savedMembers)));
                liveMembers.swap(savedMembers);
            }
        }
        machine.bus.cycles_ = staged.bus.cycles_;
        machine.cpu.r = staged.cpu.r;
        machine.cpu.waiting_ = staged.cpu.waiting_;
        machine.cpu.stopped_ = staged.cpu.stopped_;
        machine.cpu.nmiPending_ = staged.cpu.nmiPending_;
        machine.consoleOutput = staged.consoleOutput;
        machine.breakpoints.swap(staged.breakpoints);
    }
};

void Machine::saveState(const std::filesystem::path &file) const
{
    auto payload = StateCodec::encode(*this);
    Writer header;
    for (auto byte : magic)
        header(byte);
    header(version);
    header(static_cast<std::uint32_t>(payload.size()));
    header(checksum(payload));

    // Write beside the destination and rename only after a successful close.
    // Exclusive creation avoids clobbering another save's temporary file.
    std::random_device random;
    std::filesystem::path temporary;
    std::ofstream out;
    for (unsigned attempt = 0; attempt < 16 && !out.is_open(); ++attempt)
    {
        temporary = file;
        temporary += ".tmp-" + std::to_string(random());
        out.open(temporary, std::ios::binary | std::ios::out | std::ios::noreplace);
    }
    if (!out.is_open())
        throw std::runtime_error("cannot create state file: " + file.string());
    try
    {
        out.write(reinterpret_cast<const char *>(header.data.data()), header.data.size());
        out.write(reinterpret_cast<const char *>(payload.data()), payload.size());
        out.close();
        if (!out)
            throw std::runtime_error("failed writing state file: " + file.string());
        std::filesystem::rename(temporary, file);
    }
    catch (...)
    {
        out.close();
        std::error_code ignored;
        std::filesystem::remove(temporary, ignored);
        throw;
    }
}

void Machine::loadState(const std::filesystem::path &file)
{
    std::ifstream in(file, std::ios::binary);
    if (!in)
        throw std::runtime_error("cannot open state file: " + file.string());
    std::array<Byte, 20> header;
    if (!in.read(reinterpret_cast<char *>(header.data()), header.size()) ||
        !std::equal(magic.begin(), magic.end(), header.begin()))
        throw std::runtime_error("invalid state file header");
    Reader reader{std::span(header).subspan(magic.size())};
    std::uint32_t format, size, crc;
    reader(format);
    reader(size);
    reader(crc);
    if (format != version)
        throw std::runtime_error("unsupported state file version: " + std::to_string(format));
    if (size > maxPayload)
        throw std::runtime_error("state exceeds 16 MiB limit");
    std::vector<Byte> payload(size);
    if (!in.read(reinterpret_cast<char *>(payload.data()), size))
        throw std::runtime_error("truncated state file");
    if (in.peek() != std::char_traits<char>::eof() || in.bad())
        throw std::runtime_error("unexpected trailing state data or read error");
    if (checksum(payload) != crc)
        throw std::runtime_error("state file checksum mismatch");
    StateCodec::decode(*this, payload);
}
} // namespace joshua
