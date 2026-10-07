/**
 * @file core_tests.cpp
 * @brief Host-side regression checks for the portable Lightman core.
 *
 * Exercises terminal sequences, keyboard translation, PS/2 framing, configuration
 * records, generated font data and bounded parsing of malformed input.
 */
#include "config.h"
#include "fonts.h"
#include "keyboard.h"
#include "terminal.h"
#include <cassert>
#include <iostream>
#include <random>
using namespace lightman;
/**
 * @brief Execute assertion-based portable-core regression and malformed-input checks.
 * @return Zero after all checks pass; a failed assertion terminates the process.
 */
int main()
{
    std::string replies;
    Terminal t([](void *p, std::string_view s) { static_cast<std::string *>(p)->append(s); }, &replies);
    t.feed("hello\r\nworld");
    assert(t.cells()[0].ch == 'h' && t.cells()[80].ch == 'w');
    t.feed("\033[24;80HX");
    assert(t.x() == 79 && t.y() == 23);
    t.feed("Y");
    assert(t.cells()[23 * 80].ch == 'Y' && t.cells()[22 * 80 + 79].ch == 'X');
    t.reset();
    t.feed("\033[?7l\033[1;80HAB");
    assert(t.cells()[79].ch == 'B' && t.y() == 0);
    t.reset();
    t.feed("\033[5;10r\033[?6h\033[2;3H\033[6n");
    assert(t.y() == 5 && t.x() == 2 && replies == "\033[2;3R");
    t.feed("\033[99B");
    assert(t.y() == 9);
    t.feed("\033[99A");
    assert(t.y() == 4);
    t.feed("\033[7m\033(0\0337\033[0m\033(B\0338q");
    assert(t.cells()[4 * 80 + 2].attr == (Reverse | Graphics));
    t.reset();
    t.feed("ABC\033[2D\033[K");
    assert(t.cells()[0].ch == 'A' && t.cells()[1].ch == ' ');
    t.feed("\033[2J");
    assert(t.cells()[0].ch == ' ' && t.x() == 1);
    t.reset();
    t.feed("\033[2;3r\033[2;1HA\033[3;1HB\n");
    assert(t.cells()[80].ch == 'B' && t.cells()[160].ch == ' ');
    t.feed("\033[2;1H\033M");
    assert(t.cells()[160].ch == 'B');
    t.reset();
    t.feed("\033[3g\t");
    assert(t.x() == 79);
    t.reset();
    t.feed("\033[12\x18"
           "A");
    assert(t.cells()[0].ch == 'A');
    t.feed("\033]0;hidden title\033\\B");
    assert(t.cells()[1].ch == 'B');
    t.reset();
    t.feed("\033[1;2;3;4;5;6;7;8;9;10;11;12;13;14;15;16;17HZ");
    assert(t.cells()[0].ch == 'Z');
    t.reset(true);
    replies.clear();
    t.feed("\033Y%*X\033Z");
    assert(t.cells()[5 * 80 + 10].ch == 'X' && replies == "\033/Z");
    t.feed("\033H\033B\033CX");
    assert(t.cells()[81].ch == 'X');
    t.feed("\033<\033[?2l");
    assert(t.vt52());
    t.feed("\033<");
    assert(!t.vt52());
    replies.clear();
    t.feed("\033[c\033[5n");
    assert(replies == "\033[?1;0c\033[0n");
    assert(encode_key({Key::Up}, t, true) == "\033[A");
    t.feed("\033[?1h");
    assert(encode_key({Key::Up}, t, true) == "\033OA");
    t.feed("\033=");
    assert(encode_key({Key::Keypad, '1'}, t, true) == "\033Oq");
    t.reset(true);
    assert(encode_key({Key::F1}, t, true) == "\033P");
    Keyboard k;
    assert(k.feed(0x1c).character == 'a');
    k.feed(0x12);
    assert(k.feed(0x1c).character == 'A');
    k.feed(0x59);
    k.feed(0xf0);
    k.feed(0x12);
    assert(k.feed(0x1c).character == 'A');
    k.feed(0xf0);
    k.feed(0x59);
    k.feed(0x58);
    k.feed(0x58);
    assert(k.feed(0x1c).character == 'A');
    k.feed(0x14);
    assert(k.feed(0x21).character == 3);
    k.feed(0xf0);
    k.feed(0x14);
    k.feed(0xe0);
    assert(k.feed(0x75).key == Key::Up);
    k.feed(0xe0);
    k.feed(0xf0);
    assert(k.feed(0x75).key == Key::None);
    assert(k.feed(0x07).key == Key::Setup);
    k.reset();
    auto nul = k.feed(0x14);
    (void)nul;
    assert(k.feed(0x29).character == 0);
    Ps2Frame ps;
    uint32_t us = 0;
    auto frame = [&](uint8_t b, bool bad_parity = false, bool stop = true) {
        int result = ps.edge(false, us += 100);
        unsigned ones = 0;
        for (int i = 0; i < 8; ++i)
        {
            ones += (b >> i) & 1;
            result = ps.edge((b >> i) & 1, us += 100);
            assert(result < 0);
        }
        ps.edge(bool(!(ones & 1)) ^ bad_parity, us += 100);
        return ps.edge(stop, us += 100);
    };
    assert(frame(0x1c) == 0x1c);
    assert(frame(0x55, true) < 0);
    assert(frame(0x66, false, false) < 0);
    ps.edge(false, us += 100);
    ps.edge(true, us += 100);
    us += 3000;
    assert(frame(0x07) == 7);
    Config config;
    assert(config.valid() && config.color == default_normal_color);
    assert(normal_colors[config.color].rgb332 == 0xf0); // Amber: R=7, G=4, B=0.
    auto data = encode_config(config, 42);
    Config restored;
    uint32_t gen = 0;
    assert(decode_config(data.data(), restored, gen) && gen == 42 && restored.baud == 9600 &&
           restored.color == default_normal_color);
    for (unsigned i = 0; i < data.size(); ++i)
    {
        auto broken = data;
        broken[i] ^= 1;
        assert(!decode_config(broken.data(), restored, gen));
    }
    // Every preset survives flash serialization, including legacy indices 0..2.
    for (unsigned color = 0; color < normal_colors.size(); ++color)
    {
        config.color = color;
        assert(config.valid());
        auto saved = encode_config(config, 100 + color);
        assert(decode_config(saved.data(), restored, gen) && gen == 100 + color && restored.color == color);
    }
    config.color = normal_colors.size();
    assert(!config.valid());
    auto invalid_color = encode_config(config, 200); // Valid CRC, unsupported color.
    Config previous = restored;
    uint32_t previous_gen = gen;
    assert(!decode_config(invalid_color.data(), restored, gen));
    assert(restored.color == previous.color && gen == previous_gen);
    config = Config{};
    // Each RGB332 bit must drive the correct resistor, with sync held inactive.
    assert(vga_pixel(0) == 0x003 && vga_pixel(0xff) == 0x3ff);
    assert(vga_pixel(0x80) == 0x007); // R0: 470 ohms, greatest red weight.
    assert(vga_pixel(0x40) == 0x00b);
    assert(vga_pixel(0x20) == 0x013);
    assert(vga_pixel(0x10) == 0x023); // G0: 470 ohms.
    assert(vga_pixel(0x08) == 0x043);
    assert(vga_pixel(0x04) == 0x083);
    assert(vga_pixel(0x02) == 0x103); // B0: 390 ohms.
    assert(vga_pixel(0x01) == 0x203);
    assert(vga_pixel(normal_colors[default_normal_color].rgb332) == 0x03f);
    assert(normal_colors[0].rgb332 == 0xff && normal_colors[1].rgb332 == 0x1c && normal_colors[2].rgb332 == 0xfc);
    config.baud = 12345;
    assert(!config.valid());
    data = encode_config(config, 43);
    assert(!decode_config(data.data(), restored, gen));
    assert(font_data[0]['A'][5] != 0 && font_data[1]['A'][5] != 0);
    // Arbitrary serial input must keep cursor and array indices bounded.
    std::mt19937 rng(0x8080);
    t.reset();
    for (int i = 0; i < 250000; ++i)
    {
        t.feed(static_cast<uint8_t>(rng()));
        assert(t.x() >= 0 && t.x() < 80 && t.y() >= 0 && t.y() < 24);
    }
    std::cout << "Terminal, keyboard, PS/2 framing, settings and font checks passed\n";
}
