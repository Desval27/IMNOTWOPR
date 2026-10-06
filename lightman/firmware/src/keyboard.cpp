/**
 * @file keyboard.cpp
 * @brief PS/2 frame validation, scan-code set 2 decoding and key translation.
 *
 * Implements the US layout and emits sequences according to terminal modes.
 */
#include "keyboard.h"
#include <cctype>
namespace lightman
{
/**
 * @brief Sample one data bit and return a byte when a valid frame completes.
 */
int Ps2Frame::edge(bool high, uint32_t now)
{
    if (static_cast<uint32_t>(now - last_) > 2000)
    {
        bits_ = 0;
        frame_ = 0;
    }
    last_ = now;
    if (bits_ == 0 && high)
        return -1;
    if (high)
        frame_ |= 1u << bits_;
    if (++bits_ < 11)
        return -1;
    auto frame = frame_;
    bits_ = 0;
    frame_ = 0;
    unsigned parity = 0;
    for (unsigned i = 1; i <= 9; ++i)
        parity += (frame >> i) & 1;
    if (!(frame & 0x400) || !(parity & 1))
        return -1;
    return (frame >> 1) & 255;
}
/**
 * @brief Consume one scan-code byte and update keyboard state.
 */
KeyEvent Keyboard::feed(uint8_t c)
{
    if (c == 0xaa)
    {
        reset();
        return {};
    }
    if (pause_)
    {
        --pause_;
        return {};
    }
    if (c == 0xe1)
    {
        pause_ = 7;
        extended_ = release_ = false;
        return {};
    }
    if (c == 0xe0)
    {
        extended_ = true;
        return {};
    }
    if (c == 0xf0)
    {
        release_ = true;
        return {};
    }
    bool ext = extended_, up = release_;
    extended_ = release_ = false;
    const uint8_t bit = ext ? 2 : 1;
    if (c == 0x14)
    {
        if (up)
            controls_ &= ~bit;
        else
            controls_ |= bit;
        return {};
    }
    if (c == 0x11)
    {
        if (up)
            alts_ &= ~bit;
        else
            alts_ |= bit;
        return {};
    }
    if (!ext && (c == 0x12 || c == 0x59))
    {
        uint8_t b = c == 0x12 ? 1 : 2;
        if (up)
            shifts_ &= ~b;
        else
            shifts_ |= b;
        return {};
    }
    if (c == 0x58 && !ext)
    {
        if (!up && !caps_down_)
            caps_ = !caps_;
        caps_down_ = !up;
        return {};
    }
    if (up)
        return {};
    KeyEvent e{Key::None, 0, alts_ != 0};
    if (ext)
    {
        switch (c)
        {
        case 0x75:
            e.key = Key::Up;
            break;
        case 0x72:
            e.key = Key::Down;
            break;
        case 0x6b:
            e.key = Key::Left;
            break;
        case 0x74:
            e.key = Key::Right;
            break;
        case 0x6c:
            e.key = Key::Home;
            break;
        case 0x69:
            e.key = Key::End;
            break;
        case 0x70:
            e.key = Key::Insert;
            break;
        case 0x71:
            e.key = Key::Delete;
            break;
        case 0x7d:
            e.key = Key::PageUp;
            break;
        case 0x7a:
            e.key = Key::PageDown;
            break;
        case 0x5a:
            e.key = Key::Keypad;
            e.character = '\r';
            break;
        case 0x4a:
            e.key = Key::Character;
            e.character = '/';
            break;
        default:
            break;
        }
        return e;
    }
    switch (c)
    {
    case 0x07:
        e.key = Key::Setup;
        return e;
    case 0x05:
        e.key = Key::F1;
        return e;
    case 0x06:
        e.key = Key::F2;
        return e;
    case 0x04:
        e.key = Key::F3;
        return e;
    case 0x0c:
        e.key = Key::F4;
        return e;
    case 0x5a:
        e.key = Key::Enter;
        return e;
    case 0x66:
        e.key = Key::Backspace;
        return e;
    case 0x76:
        e.key = Key::Escape;
        return e;
    case 0x0d:
        e.key = Key::Tab;
        return e;
    default:
        break;
    }
    constexpr uint8_t pads[] = {0x70, 0x69, 0x72, 0x7a, 0x6b, 0x73, 0x74, 0x6c, 0x75, 0x7d, 0x71, 0x7b, 0x79, 0x7c};
    constexpr char padchars[] = "0123456789.-+*";
    for (unsigned i = 0; i < sizeof pads; ++i)
        if (c == pads[i])
        {
            e.key = Key::Keypad;
            e.character = padchars[i];
            return e;
        }
    struct Map
    {
        uint8_t code;
        char plain, shift;
    };
    static constexpr Map map[] = {
        {0x1c, 'a', 'A'}, {0x32, 'b', 'B'},  {0x21, 'c', 'C'}, {0x23, 'd', 'D'}, {0x24, 'e', 'E'}, {0x2b, 'f', 'F'},
        {0x34, 'g', 'G'}, {0x33, 'h', 'H'},  {0x43, 'i', 'I'}, {0x3b, 'j', 'J'}, {0x42, 'k', 'K'}, {0x4b, 'l', 'L'},
        {0x3a, 'm', 'M'}, {0x31, 'n', 'N'},  {0x44, 'o', 'O'}, {0x4d, 'p', 'P'}, {0x15, 'q', 'Q'}, {0x2d, 'r', 'R'},
        {0x1b, 's', 'S'}, {0x2c, 't', 'T'},  {0x3c, 'u', 'U'}, {0x2a, 'v', 'V'}, {0x1d, 'w', 'W'}, {0x22, 'x', 'X'},
        {0x35, 'y', 'Y'}, {0x1a, 'z', 'Z'},  {0x16, '1', '!'}, {0x1e, '2', '@'}, {0x26, '3', '#'}, {0x25, '4', '$'},
        {0x2e, '5', '%'}, {0x36, '6', '^'},  {0x3d, '7', '&'}, {0x3e, '8', '*'}, {0x46, '9', '('}, {0x45, '0', ')'},
        {0x0e, '`', '~'}, {0x4e, '-', '_'},  {0x55, '=', '+'}, {0x54, '[', '{'}, {0x5b, ']', '}'}, {0x5d, '\\', '|'},
        {0x4c, ';', ':'}, {0x52, '\'', '"'}, {0x41, ',', '<'}, {0x49, '.', '>'}, {0x4a, '/', '?'}, {0x29, ' ', ' '}};
    for (auto m : map)
        if (m.code == c)
        {
            bool shift = shifts_ != 0;
            if (m.plain >= 'a' && m.plain <= 'z')
                shift ^= caps_;
            char ch = shift ? m.shift : m.plain;
            if (controls_)
            {
                if (ch == ' ' || ch == '@' || ch == '2')
                    ch = 0;
                else if (ch == '?')
                    ch = 127;
                else if ((ch >= 'a' && ch <= 'z') || (ch >= '@' && ch <= '_'))
                    ch &= 31;
            }
            e.key = Key::Character;
            e.character = ch;
            return e;
        }
    return e;
}
/**
 * @brief Encode a logical key using the current terminal modes.
 */
std::string encode_key(KeyEvent e, const Terminal &t, bool del)
{
    std::string s;
    switch (e.key)
    {
    case Key::Character:
        s += e.character;
        break;
    case Key::Enter:
        s = t.newline() ? "\r\n" : "\r";
        break;
    case Key::Backspace:
        s += del ? '\x7f' : '\b';
        break;
    case Key::Escape:
        s = "\033";
        break;
    case Key::Tab:
        s = "\t";
        break;
    case Key::Up:
    case Key::Down:
    case Key::Right:
    case Key::Left: {
        char c = e.key == Key::Up ? 'A' : e.key == Key::Down ? 'B' : e.key == Key::Right ? 'C' : 'D';
        s = t.vt52() ? "\033" : t.application_cursor() ? "\033O" : "\033[";
        s += c;
        break;
    }
    case Key::F1:
    case Key::F2:
    case Key::F3:
    case Key::F4:
        s = t.vt52() ? "\033" : "\033O";
        s += char('P' + int(e.key) - int(Key::F1));
        break;
    case Key::Keypad:
        if (t.application_keypad() && e.character != '+' && e.character != '*')
        {
            s = t.vt52() ? "\033?" : "\033O";
            s += e.character == '\r'  ? 'M'
                 : e.character == '.' ? 'n'
                 : e.character == '-' ? 'm'
                                      : char('p' + e.character - '0');
        }
        else if (e.character == '\r')
            s = t.newline() ? "\r\n" : "\r";
        else
            s += e.character;
        break;
    case Key::Home:
        s = t.vt52() ? "\033H" : "\033[H";
        break;
    case Key::End:
        s = "\033[F";
        break;
    case Key::Insert:
        s = "\033[2~";
        break;
    case Key::Delete:
        s = "\033[3~";
        break;
    case Key::PageUp:
        s = "\033[5~";
        break;
    case Key::PageDown:
        s = "\033[6~";
        break;
    default:
        break;
    }
    if (e.alt && !s.empty())
        s.insert(s.begin(), 27);
    return s;
}
} // namespace lightman
