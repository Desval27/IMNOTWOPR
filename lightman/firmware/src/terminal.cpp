/**
 * @file terminal.cpp
 * @brief VT100/VT52 byte-stream parsing and text-screen operations.
 *
 * Implements bounded escape parsing, cursor movement, scrolling and terminal replies.
 */
#include "terminal.h"
#include <algorithm>
#include <cstdio>

namespace lightman
{
/**
 * @brief Construct a cleared terminal with default VT100 modes.
 */
Terminal::Terminal(Output output, void *context) : output_(output), context_(context)
{
    reset();
}
/**
 * @brief Clear the screen and restore default cursor, tabs, modes and saved state.
 */
void Terminal::reset(bool vt52)
{
    screen_.fill(Cell{});
    tabs_.fill(false);
    for (int i = 8; i < columns; i += 8)
        tabs_[i] = true;
    x_ = y_ = top_ = 0;
    bottom_ = rows - 1;
    attr_ = 0;
    vt52_ = vt52;
    app_cursor_ = app_keypad_ = newline_ = origin_ = pending_wrap_ = false;
    reverse_screen_ = keyboard_locked_ = false;
    wrap_ = cursor_visible_ = true;
    graphics_[0] = graphics_[1] = false;
    active_charset_ = 0;
    state_ = State::Text;
    save();
}
/**
 * @brief Process a byte span in order without resetting parser state.
 */
void Terminal::feed(std::string_view text)
{
    for (unsigned char c : text)
        feed(c);
}
/**
 * @brief Deliver a host reply through the optional output callback.
 */
void Terminal::reply(std::string_view text)
{
    if (output_)
        output_(context_, text);
}
/**
 * @brief Clamp a requested cursor position and cancel pending wrapping.
 */
void Terminal::move(int x, int y)
{
    x_ = std::clamp(x, 0, columns - 1);
    y_ = std::clamp(y, origin_ ? top_ : 0, origin_ ? bottom_ : rows - 1);
    pending_wrap_ = false;
}
/**
 * @brief Replace a contiguous cell range with blank, unstyled cells.
 */
void Terminal::erase(int first, int last)
{
    std::fill(screen_.begin() + first, screen_.begin() + last, Cell{});
}
/**
 * @brief Scroll the active margin region by one row and blank the exposed row.
 */
void Terminal::scroll(int direction)
{
    const int first = top_ * columns, last = (bottom_ + 1) * columns;
    if (direction > 0)
    {
        std::move(screen_.begin() + first + columns, screen_.begin() + last, screen_.begin() + first);
        erase(last - columns, last);
    }
    else
    {
        std::move_backward(screen_.begin() + first, screen_.begin() + last - columns, screen_.begin() + last);
        erase(first, first + columns);
    }
}
/**
 * @brief Move one line vertically, scrolling at the applicable margin.
 */
void Terminal::index(bool reverse)
{
    pending_wrap_ = false;
    if (reverse)
    {
        if (y_ == top_)
            scroll(-1);
        else if (y_ > 0)
            --y_;
    }
    else
    {
        if (y_ == bottom_)
            scroll(1);
        else if (y_ < rows - 1)
            ++y_;
    }
}
/**
 * @brief Write a printable character with current attributes and delayed wrapping.
 */
void Terminal::put(uint8_t ch)
{
    if (pending_wrap_ && wrap_)
    {
        x_ = 0;
        index();
    }
    pending_wrap_ = false;
    screen_[y_ * columns + x_] = {ch, static_cast<uint8_t>(attr_ | (graphics_[active_charset_] ? Graphics : 0))};
    if (x_ == columns - 1)
        pending_wrap_ = wrap_;
    else
        ++x_;
}
/**
 * @brief Save cursor, rendition, character sets, origin and wrapping modes.
 */
void Terminal::save()
{
    saved_x_ = x_;
    saved_y_ = y_;
    saved_attr_ = attr_;
    saved_origin_ = origin_;
    saved_wrap_ = wrap_;
    saved_charset_ = active_charset_;
    std::copy_n(graphics_, 2, saved_graphics_);
}
/**
 * @brief Restore saved cursor and modes, clamping the cursor to valid bounds.
 */
void Terminal::restore()
{
    origin_ = saved_origin_;
    wrap_ = saved_wrap_;
    attr_ = saved_attr_;
    active_charset_ = saved_charset_;
    std::copy_n(saved_graphics_, 2, graphics_);
    move(saved_x_, saved_y_);
}
/**
 * @brief Dispatch the byte following ESC in the current emulation mode.
 */
void Terminal::escape(uint8_t c)
{
    state_ = State::Text;
    if (vt52_)
    {
        switch (c)
        {
        case 'A':
            move(x_, y_ - 1);
            break;
        case 'B':
            move(x_, y_ + 1);
            break;
        case 'C':
            move(x_ + 1, y_);
            break;
        case 'D':
            move(x_ - 1, y_);
            break;
        case 'H':
            move(0, 0);
            break;
        case 'I':
            index(true);
            break;
        case 'J':
            erase(y_ * columns + x_, columns * rows);
            break;
        case 'K':
            erase(y_ * columns + x_, (y_ + 1) * columns);
            break;
        case 'Y':
            state_ = State::Row52;
            break;
        case 'Z':
            reply("\033/Z");
            break;
        case 'F':
            graphics_[0] = true;
            active_charset_ = 0;
            break;
        case 'G':
            graphics_[0] = false;
            active_charset_ = 0;
            break;
        case '=':
            app_keypad_ = true;
            break;
        case '>':
            app_keypad_ = false;
            break;
        case '<':
            vt52_ = false;
            break;
        default:
            break;
        }
        return;
    }
    switch (c)
    {
    case '[':
        params_.fill(0);
        count_ = 1;
        private_ = invalid_ = false;
        state_ = State::Csi;
        break;
    case '(':
    case ')':
        charset_ = c == ')';
        state_ = State::Charset;
        break;
    case '#':
        state_ = State::Hash;
        break;
    case ']':
    case 'P':
    case '^':
    case '_':
        state_ = State::String;
        break;
    case '7':
        save();
        break;
    case '8':
        restore();
        break;
    case 'D':
        index();
        break;
    case 'M':
        index(true);
        break;
    case 'E':
        x_ = 0;
        index();
        break;
    case 'H':
        tabs_[x_] = true;
        break;
    case '=':
        app_keypad_ = true;
        break;
    case '>':
        app_keypad_ = false;
        break;
    case 'Z':
        reply("\033[?1;0c");
        break;
    case 'c':
        reset();
        break;
    default:
        break;
    }
}
/**
 * @brief Dispatch a completed CSI sequence using the accumulated parameters.
 */
void Terminal::csi(uint8_t final)
{
    const auto p = [this](int i, int fallback = 1) { return i < count_ && params_[i] ? params_[i] : fallback; };
    const int n = p(0);
    if (private_ && final != 'h' && final != 'l')
        return;
    switch (final)
    {
    case 'A':
        move(x_, std::max(y_ - n, y_ >= top_ ? top_ : 0));
        break;
    case 'B':
        move(x_, std::min(y_ + n, y_ <= bottom_ ? bottom_ : rows - 1));
        break;
    case 'C':
        move(x_ + n, y_);
        break;
    case 'D':
        move(x_ - n, y_);
        break;
    case 'H':
    case 'f':
        move(p(1) - 1, p(0) - 1 + (origin_ ? top_ : 0));
        break;
    case 'J':
        if (params_[0] == 0)
            erase(y_ * columns + x_, columns * rows);
        else if (params_[0] == 1)
            erase(0, y_ * columns + x_ + 1);
        else if (params_[0] == 2)
            erase(0, columns * rows);
        break;
    case 'K':
        if (params_[0] == 0)
            erase(y_ * columns + x_, (y_ + 1) * columns);
        else if (params_[0] == 1)
            erase(y_ * columns, y_ * columns + x_ + 1);
        else if (params_[0] == 2)
            erase(y_ * columns, (y_ + 1) * columns);
        break;
    case 'm':
        for (int i = 0; i < count_; ++i)
            switch (params_[i])
            {
            case 0:
                attr_ = 0;
                break;
            case 1:
                attr_ |= Bold;
                break;
            case 4:
                attr_ |= Underline;
                break;
            case 5:
                attr_ |= Blink;
                break;
            case 7:
                attr_ |= Reverse;
                break;
            case 22:
                attr_ &= ~Bold;
                break;
            case 24:
                attr_ &= ~Underline;
                break;
            case 25:
                attr_ &= ~Blink;
                break;
            case 27:
                attr_ &= ~Reverse;
                break;
            default:
                break;
            }
        break;
    case 'r': {
        int t = p(0) - 1, b = p(1, rows) - 1;
        if (t >= 0 && b < rows && t < b)
        {
            top_ = t;
            bottom_ = b;
            move(0, origin_ ? top_ : 0);
        }
        break;
    }
    case 'g':
        if (params_[0] == 0)
            tabs_[x_] = false;
        else if (params_[0] == 3)
            tabs_.fill(false);
        break;
    case 'h':
    case 'l':
        for (int i = 0; i < count_; ++i)
        {
            const bool on = final == 'h';
            if (private_)
                switch (params_[i])
                {
                case 1:
                    app_cursor_ = on;
                    break;
                case 2:
                    if (!on)
                    {
                        vt52_ = true;
                        origin_ = false;
                    }
                    break;
                case 5:
                    reverse_screen_ = on;
                    break;
                case 6:
                    origin_ = on;
                    move(0, on ? top_ : 0);
                    break;
                case 7:
                    wrap_ = on;
                    pending_wrap_ = false;
                    break;
                case 25:
                    cursor_visible_ = on;
                    break;
                default:
                    break;
                }
            else if (params_[i] == 20)
                newline_ = on;
            else if (params_[i] == 2)
                keyboard_locked_ = on;
        }
        break;
    case 'c':
        if (params_[0] == 0)
            reply("\033[?1;0c");
        break;
    case 'n':
        if (params_[0] == 5)
            reply("\033[0n");
        else if (params_[0] == 6)
        {
            char response[24];
            std::snprintf(response, sizeof response, "\033[%d;%dR", y_ + 1 - (origin_ ? top_ : 0), x_ + 1);
            reply(response);
        }
        break;
    default:
        break;
    }
}
/**
 * @brief Process one host byte, retaining any incomplete escape sequence.
 */
void Terminal::feed(uint8_t c)
{
    if (c == 0x18 || c == 0x1a)
    {
        state_ = State::Text;
        return;
    }
    if (state_ == State::String || state_ == State::StringEscape)
    {
        if (c == 7 || (state_ == State::StringEscape && c == '\\'))
            state_ = State::Text;
        else
            state_ = c == 27 ? State::StringEscape : State::String;
        return;
    }
    if (c == 27)
    {
        state_ = State::Escape;
        return;
    }
    if (c < 32 || c == 127)
    {
        switch (c)
        {
        case 7:
            ++bells;
            break;
        case 8:
            move(x_ - 1, y_);
            break;
        case 9: {
            int x = x_ + 1;
            while (x < columns - 1 && !tabs_[x])
                ++x;
            move(x, y_);
            break;
        }
        case 10:
        case 11:
        case 12:
            if (newline_)
                x_ = 0;
            index();
            break;
        case 13:
            move(0, y_);
            break;
        case 14:
            active_charset_ = 1;
            break;
        case 15:
            active_charset_ = 0;
            break;
        default:
            break;
        }
        return;
    }
    switch (state_)
    {
    case State::Text:
        if (c < 127)
            put(c);
        break;
    case State::Escape:
        escape(c);
        break;
    case State::Charset:
        graphics_[charset_] = c == '0';
        state_ = State::Text;
        break;
    case State::Hash:
        if (c == '8')
        {
            screen_.fill(Cell{'E', 0});
            move(0, 0);
        }
        state_ = State::Text;
        break;
    case State::Row52:
        move(x_, static_cast<int>(c) - 32);
        state_ = State::Col52;
        break;
    case State::Col52:
        move(static_cast<int>(c) - 32, y_);
        state_ = State::Text;
        break;
    case State::Csi:
        if (c >= '0' && c <= '9')
            params_[count_ - 1] = std::min(9999, params_[count_ - 1] * 10 + c - '0');
        else if (c == ';')
        {
            if (count_ < static_cast<int>(params_.size()))
                ++count_;
            else
                invalid_ = true;
        }
        else if (c == '?' && count_ == 1 && params_[0] == 0 && !private_)
            private_ = true;
        else if (c >= 0x40 && c <= 0x7e)
        {
            if (!invalid_)
                csi(c);
            state_ = State::Text;
        }
        else
            invalid_ = true;
        break;
    default:
        state_ = State::Text;
        break;
    }
}
} // namespace lightman
