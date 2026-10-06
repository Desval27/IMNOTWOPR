/**
 * @file terminal.h
 * @brief Portable 80-column, 24-row VT100/VT52 terminal state and parser.
 *
 * Owns screen cells, cursor state, character sets and host-controlled modes.
 * Hardware rendering and serial transport are supplied separately.
 */
#pragma once
#include <array>
#include <cstdint>
#include <string_view>

namespace lightman
{
constexpr int columns = 80, rows = 24;
/**
 * @brief Bit flags attached to each displayed character.
 */
enum Attribute : uint8_t
{
    Bold = 1,
    Underline = 2,
    Blink = 4,
    Reverse = 8,
    Graphics = 16
};
/**
 * @brief Character code and display attributes for one text cell.
 */
struct Cell
{
    uint8_t ch = ' ', attr = 0;
};
/**
 * @brief Stateful VT100/VT52 parser owning an 80 by 24 text screen.
 *
 * Call from one execution context. Rendering must not race feed() or reset().
 */
class Terminal
{
  public:
    /**
     * @brief Synchronous host-reply callback receiving the context pointer and reply bytes.
     * @note The string view is valid only during the callback; copy it if retaining data.
     */
    using Output = void (*)(void *, std::string_view);
    /**
     * @brief Construct a cleared terminal with default VT100 modes.
     * @param output Optional callback for identity/status replies; null discards replies.
     * @param context Opaque value passed to output on every reply.
     */
    explicit Terminal(Output output = nullptr, void *context = nullptr);
    /**
     * @brief Clear the screen and restore default cursor, tabs, modes and saved state.
     * @param vt52 True to start in VT52 mode; false to start in VT100/ANSI mode.
     * @note The accumulated bell counter is preserved.
     */
    void reset(bool vt52 = false);
    /**
     * @brief Process one host byte, retaining any incomplete escape sequence.
     * @param byte Incoming control or character byte; printable text is 7-bit ASCII.
     * @note Processing may synchronously invoke the Output callback.
     */
    void feed(uint8_t byte);
    /**
     * @brief Process a byte span in order without resetting parser state.
     * @param text Host bytes; embedded NULs are processed and no storage is retained.
     */
    void feed(std::string_view text);
    /**
     * @brief Read the current row-major text cells.
     * @return A reference owned by this terminal; contents change with subsequent input.
     */
    const std::array<Cell, columns * rows> &cells() const
    {
        return screen_;
    }
    /**
     * @brief Read the cursor column.
     * @return Zero-based column in the range 0..columns-1.
     */
    int x() const
    {
        return x_;
    }
    /**
     * @brief Read the absolute cursor row.
     * @return Zero-based screen row in the range 0..rows-1, even in origin mode.
     */
    int y() const
    {
        return y_;
    }
    /**
     * @brief Read the active emulation mode.
     * @return True for VT52; false for VT100/ANSI.
     */
    bool vt52() const
    {
        return vt52_;
    }
    /**
     * @brief Read the cursor-key encoding mode.
     * @return True when ANSI cursor keys use application sequences.
     */
    bool application_cursor() const
    {
        return app_cursor_;
    }
    /**
     * @brief Read the numeric-keypad encoding mode.
     * @return True when keypad keys use application sequences.
     */
    bool application_keypad() const
    {
        return app_keypad_;
    }
    /**
     * @brief Read line-feed/newline mode.
     * @return True when received LF also returns to column zero and Enter sends CR/LF.
     */
    bool newline() const
    {
        return newline_;
    }
    /**
     * @brief Read the requested cursor visibility.
     * @return True when the renderer should display the cursor.
     */
    bool cursor_visible() const
    {
        return cursor_visible_;
    }
    /**
     * @brief Read the global reverse-video mode.
     * @return True when the renderer should invert screen-cell polarity.
     */
    bool reverse_screen() const
    {
        return reverse_screen_;
    }
    /**
     * @brief Read the host-requested keyboard lock.
     * @return True when ordinary key transmission should be suppressed; local setup remains available.
     */
    bool keyboard_locked() const
    {
        return keyboard_locked_;
    }
    /**
     * @brief Count of received BEL controls, modulo 2^32, for the frontend indicator.
     */
    uint32_t bells = 0;

  private:
    enum class State
    {
        Text,
        Escape,
        Csi,
        Charset,
        Hash,
        Row52,
        Col52,
        String,
        StringEscape
    };
    std::array<Cell, columns * rows> screen_{};
    std::array<bool, columns> tabs_{};
    std::array<int, 16> params_{};
    int x_ = 0, y_ = 0, top_ = 0, bottom_ = rows - 1, count_ = 1, charset_ = 0;
    int saved_x_ = 0, saved_y_ = 0;
    uint8_t attr_ = 0, saved_attr_ = 0;
    bool vt52_ = false, app_cursor_ = false, app_keypad_ = false, newline_ = false;
    bool origin_ = false, wrap_ = true, pending_wrap_ = false, cursor_visible_ = true;
    bool reverse_screen_ = false, keyboard_locked_ = false, private_ = false, invalid_ = false;
    bool graphics_[2]{}, saved_graphics_[2]{}, saved_origin_ = false, saved_wrap_ = true;
    int active_charset_ = 0, saved_charset_ = 0;
    State state_ = State::Text;
    Output output_;
    void *context_;
    /**
     * @brief Deliver a host reply through the optional output callback.
     * @param text Reply bytes valid for the duration of the synchronous call.
     */
    void reply(std::string_view text);
    /**
     * @brief Write a printable character with current attributes and delayed wrapping.
     * @param ch Character code to store at the cursor.
     */
    void put(uint8_t ch);
    /**
     * @brief Clamp a requested cursor position and cancel pending wrapping.
     * @param x Requested zero-based column.
     * @param y Requested absolute row, clamped to margins when origin mode is enabled.
     */
    void move(int x, int y);
    /**
     * @brief Move one line vertically, scrolling at the applicable margin.
     * @param reverse True for reverse index (up); false for index (down).
     */
    void index(bool reverse = false);
    /**
     * @brief Scroll the active margin region by one row and blank the exposed row.
     * @param direction Positive scrolls up; zero or negative scrolls down.
     */
    void scroll(int direction);
    /**
     * @brief Replace a contiguous cell range with blank, unstyled cells.
     * @param first Inclusive row-major cell offset.
     * @param last Exclusive row-major cell offset.
     * @pre 0 <= first <= last <= columns * rows.
     */
    void erase(int first, int last);
    /**
     * @brief Dispatch a completed CSI sequence using the accumulated parameters.
     * @param final Final command byte; unsupported commands have no effect.
     */
    void csi(uint8_t final);
    /**
     * @brief Dispatch the byte following ESC in the current emulation mode.
     * @param byte Escape command byte, which may start a longer parser sequence.
     */
    void escape(uint8_t byte);
    /**
     * @brief Save cursor, rendition, character sets, origin and wrapping modes.
     */
    void save();
    /**
     * @brief Restore saved cursor and modes, clamping the cursor to valid bounds.
     */
    void restore();
};
} // namespace lightman
