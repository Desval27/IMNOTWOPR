/**
 * @file keyboard.h
 * @brief Portable PS/2 framing, US scan-code decoding and terminal key encoding.
 *
 * Separates electrical frame assembly from scan-code state and outgoing escape sequences.
 */
#pragma once
#include "terminal.h"
#include <cstdint>
#include <string>
namespace lightman
{
/**
 * @brief Logical keys understood by setup and the terminal encoder.
 */
enum class Key
{
    None,
    Character,
    Enter,
    Backspace,
    Escape,
    Tab,
    Up,
    Down,
    Left,
    Right,
    Home,
    End,
    Insert,
    Delete,
    PageUp,
    PageDown,
    F1,
    F2,
    F3,
    F4,
    Setup,
    Keypad
};
/**
 * @brief Decoded key press, optional character payload and Alt modifier.
 *
 * The character field may contain NUL; use key, not the character value, to
 * determine whether an event is present.
 */
struct KeyEvent
{
    Key key = Key::None;
    char character = 0;
    bool alt = false;
};
/**
 * @brief Stateful decoder for a US keyboard using PS/2 scan-code set 2.
 *
 * Tracks prefixes and independent modifiers; release codes do not emit key presses.
 */
class Keyboard
{
  public:
    /**
     * @brief Consume one scan-code byte and update keyboard state.
     * @param scancode Byte from a validated PS/2 frame.
     * @return A decoded press, or Key::None for prefixes, releases and unsupported codes.
     * @note A keyboard BAT success byte resets decoder state.
     */
    KeyEvent feed(uint8_t scancode);
    /**
     * @brief Clear prefixes, held modifiers, Caps Lock and Pause-sequence state.
     */
    void reset()
    {
        *this = Keyboard{};
    }

  private:
    bool extended_ = false, release_ = false, caps_ = false, caps_down_ = false;
    uint8_t shifts_ = 0, controls_ = 0, alts_ = 0, pause_ = 0;
};
/**
 * @brief Encode a logical key using the current terminal modes.
 * @param event Key press and modifier state; Alt adds an ESC prefix.
 * @param terminal Supplies VT52, application cursor/keypad and newline modes.
 * @param backspace_del True to send DEL for Backspace; false to send BS.
 * @return Bytes to transmit, possibly containing NUL, or empty for a local/unused key.
 */
std::string encode_key(KeyEvent event, const Terminal &terminal, bool backspace_del);
// PS/2 set 2 frames: start, eight LSB-first data bits, odd parity, stop.
/**
 * @brief Assemble 11-bit PS/2 frames from falling clock edges.
 *
 * Frames use a low start bit, eight LSB-first data bits, odd parity and a high
 * stop bit. Gaps longer than 2 ms discard an incomplete frame.
 */
class Ps2Frame
{
  public:
    /**
     * @brief Sample one data bit and return a byte when a valid frame completes.
     * @param high Data-line level sampled on the falling clock edge.
     * @param time_us Monotonic microsecond timestamp, wrapping at 32 bits.
     * @return The decoded byte in 0..255, or -1 for incomplete or invalid input.
     */
    int edge(bool high, uint32_t time_us);

  private:
    uint16_t frame_ = 0;
    unsigned bits_ = 0;
    uint32_t last_ = 0;
};
} // namespace lightman
