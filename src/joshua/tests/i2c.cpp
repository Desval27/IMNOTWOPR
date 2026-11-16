#include "joshua/devices.hpp"
#include <iostream>
#include <stdexcept>

using namespace joshua;
namespace
{
void check(bool condition, const char *message)
{
    if (!condition)
        throw std::runtime_error(message);
}

// Drive actual VIA registers, preserving unrelated port bits. SDA/SCL are
// released by DDR=0; ORB remains zero on the two bus pins, as in the ROM driver.
struct Controller
{
    Via &via;
    void lines(bool scl, bool sda)
    {
        via.write(2, 0x0f | (scl ? 0 : 0x40) | (sda ? 0 : 0x80));
        check((via.peek(0) & 0x3f) == 0x25, "I2C changed unrelated port bits");
    }
    void start()
    {
        lines(false, true);
        lines(true, true);
        lines(true, false);
        lines(false, false);
    }
    void stop()
    {
        lines(false, false);
        lines(true, false);
        lines(true, true);
        check((via.peek(0) & 0xc0) == 0xc0, "STOP did not release bus");
    }
    void bits(Byte value)
    {
        for (int bit = 7; bit >= 0; --bit)
        {
            bool sda = value & (1 << bit);
            lines(false, sda);
            lines(true, sda);
            check(bool(via.peek(0) & 0x80) == sda, "target drove SDA before ACK clock");
            lines(false, sda);
        }
    }
    bool ack()
    {
        lines(false, true);
        lines(true, true);
        const bool result = !(via.read(0) & 0x80);
        for (unsigned i = 0; i < 10; ++i)
        {
            via.tick();
            check(bool(via.peek(0) & 0x80) == !result, "ACK changed during ninth high period");
        }
        lines(false, true);
        check(via.peek(0) & 0x80, "target did not release after ACK");
        return result;
    }
    bool send(Byte value) { bits(value); return ack(); }
};

void exerciseTargets()
{
    Via via({0x77, 0x08, 0x3c, 0x68});
    via.reset();
    via.setPortB(0xea);
    via.write(0, 0x15);
    Controller controller{via};
    controller.lines(true, true);
    for (unsigned pass = 0; pass < 2; ++pass)
        for (unsigned address = 0; address < 128; ++address)
        {
            const bool present = address == 0x08 || address == 0x3c || address == 0x68 || address == 0x77;
            controller.start();
            check(controller.send(address << 1) == present, "wrong write address response");
            // A payload resembling an address must not start another transaction.
            check(!controller.send(0x78), "address-only target acknowledged payload");
            controller.start(); // Repeated START without STOP must reset the decoder.
            check(!controller.send((address << 1) | 1), "address-only target acknowledged read");
            controller.start();
            check(controller.send(0xd0), "repeated START lost configured target");
            controller.stop();
        }

    controller.start();
    controller.bits(0x78);
    controller.lines(false, true);
    check(!(via.peek(0) & 0x80), "target did not assert ACK before reset");
    via.reset();
    check((via.peek(0) & 0xc0) == 0xc0, "reset left target driving bus");
    via.write(0, 0x15);
    controller.start();
    check(controller.send(0x78), "reset removed configured target");
    controller.stop();

    // External SCL low suppresses clock edges even when the controller releases it.
    controller.start();
    via.setPortB(0xaa);
    controller.lines(true, true);
    check(!(via.peek(0) & 0x40), "external SCL low was ignored");
    via.setPortB(0xea);
    controller.stop();
    controller.start();
    check(controller.send(0x78), "bus did not recover after external SCL release");
    controller.stop();
}

void emptyBus()
{
    Via via;
    via.reset();
    via.setPortB(0xea);
    via.write(0, 0x15);
    Controller controller{via};
    controller.start();
    check(!controller.send(0x78), "unconfigured bus acknowledged address");
    controller.stop();
}
}

int main()
{
    try
    {
        exerciseTargets();
        emptyBus();
        std::cout << "I2C checks passed.\n";
    }
    catch (const std::exception &error)
    {
        std::cerr << "FAIL: " << error.what() << '\n';
        return 1;
    }
}
