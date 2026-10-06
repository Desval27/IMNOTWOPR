# Terminal compatibility baseline

This is an initial useful VT100/VT52 subset, not a conformance-certified DEC
terminal. Use ASCII, 80 columns and 24 rows. Host applications should avoid
features listed as unsupported below. There is no Unicode/UTF-8 decoder.

The implementation follows the
[DEC VT100 User Guide, chapter 3](https://www.vintagecomputer.net/digital/VT100/vt100_manual/chapter3.html).

## Implemented

| Area | Behavior |
| --- | --- |
| C0 controls | BS, HT, LF/VT/FF, CR, SO/SI; BEL flashes the Pico LED |
| ANSI cursor | CUU/CUD/CUF/CUB, CUP/HVP, index, reverse index, next line |
| Erasing | ED and EL modes 0, 1, 2 |
| Scrolling | DECSTBM top/bottom margins; origin-relative addressing; delayed wrap |
| Attributes | SGR reset, bold (bold font), underline, blink, reverse; 22/24/25/27 resets |
| Tabs | Every eight columns by default; ESC H; CSI 0g/3g |
| Saved state | ESC 7/8: cursor, rendition, origin/wrap modes and G0/G1 selection |
| Modes | DECCKM, DECANM, DECOM, DECAWM, DECSCNM, LNM, keyboard lock; cursor visibility extension |
| Identification | DA replies ESC [ ? 1 ; 0 c (VT100, no options); DSR 5/6 |
| Character sets | G0/G1 ASCII and DEC special graphics, SO/SI selection |
| Reset/test | RIS (ESC c); DECALN (ESC # 8) |
| VT52 | ESC A/B/C/D, H, I, J, K, Y row/column, Z, F/G, =/>, < |
| VT52 identity | ESC / Z; ESC < enters ANSI mode; ANSI CSI ? 2 l enters VT52 |
| Keys | US set 2 PS/2 typing, Shift/Caps/Ctrl/Alt, arrows, F1–F4 as PF1–PF4 |
| Keypad | Numeric/application digits, decimal, minus, Enter; ANSI/VT52 forms |
| Additional PC keys | Home, End, Insert, Delete, Page Up/Down use common ANSI extensions |

Alt prefixes transmitted key sequences with ESC. F12 is always local setup,
even with host keyboard lock active. Backspace sends DEL by default and can
be changed to BS in setup. Enter sends CR, or CR/LF when the host enables LNM.
Keypad plus, multiply and divide remain literal characters; Num Lock does not
change the numeric keypad. Caps Lock is tracked locally without setting the
keyboard's LED. Holding keys uses the keyboard's own repeat behavior.

DEC box-drawing, scan lines, diamond and checkerboard glyphs are drawn locally.
Some mathematical/control-picture symbols are ASCII approximations. VT52 F/G
uses the same graphics repertoire, rather than a distinct historical VT52 ROM.

## Deliberate gaps

- 132-column mode, double-width/double-height lines, smooth scrolling.
- Exact historical VT52 graphics, UK national character set, full DEC font ROM.
- ANSI color SGR, Unicode, alternate screen, scrollback, and xterm features.
- VT102 insert/delete characters and lines, printer support, answerback,
  keyboard LED commands, confidence tests and serial BREAK generation.
- USB keyboard input, keyboard host commands, non-US layouts and F5–F11.
- Modem dialing, automatic carrier/ring handling and DTR hangup control.

Unsupported CSI sequences are consumed without printing them. CSI parameter
count/value limits prevent malformed streams from overrunning buffers. OSC/DCS
strings are discarded through BEL or ST. CAN/SUB abort an in-progress sequence.

## Communication and storage

Default: **9600 baud, 8N1, no flow control, VT100, no local echo, DEL Backspace,
regular font, white text**. Setup supports 300–115200 baud, 7/8 bits, 1/2 stop
bits, none/even/odd parity and no/software/hardware flow control.

The RX ring holds 4095 bytes and TX ring 1023 bytes. XON/XOFF and software-driven
RTS use 75%/25% RX thresholds. UART hardware gates outgoing bytes on CTS when
selected. Flow-control characters bypass a paused TX queue. Setup requests
that the peer pause; incoming data still updates the separate terminal buffer.
Overrun/framing/parity errors and queue drops appear in setup. An overflowing
TX queue discards a complete key/reply sequence, never just its suffix.

DSR, DCD and RI are active-low status inputs displayed live in setup. They do
not gate serial traffic or trigger modem actions. RI is sampled, not latched;
brief pulses between display updates may not be visible. DTR stays asserted.

Pause host output before applying framing changes or saving. Saving erases
flash with interrupts temporarily disabled and video stopped, so an
uncooperative host can lose data. The VGA monitor may briefly lose sync.
Two alternating 4 KiB sectors at flash offsets 0x1FE000 and 0x1FF000 store
versioned, CRC32-checked records. The previous record remains intact during
the next erase/write. Invalid records fall back to defaults; a linker assertion
prevents firmware growth into these sectors. Ordinary UF2 updates leave the
settings area untouched, but a full-chip erase removes settings.
