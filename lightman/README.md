# lightman

Lightman is a Raspberry Pi Pico (RP2040) serial terminal with VGA output,
PS/2 keyboard input, and a DTE male DE-9 RS-232 port through MAX3232 transceivers.

The firmware baseline provides 80x24 text, common VT100/VT52 controls, a US
keyboard layout, buffered UART I/O, an on-device setup menu, and two embedded
fonts. It builds to a Pico UF2. Host tests and cross-compilation are verified;
physical VGA/PS/2/serial operation still needs prototype validation. See the
[compatibility matrix](docs/compatibility.md) for implemented sequences and gaps.

## Build and flash

Dependencies: CMake 3.24+, Python 3, an Arm GNU embedded C/C++ compiler with
C++23 support, and the official Pico SDK (tested: SDK 2.2.0 and GCC 13.2.1).
The SDK builds/downloads `pioasm` and `picotool` if needed. Initialize SDK
submodules for a complete SDK checkout; USB is not used by this firmware.

From the repository root:

```sh
git clone --branch 2.2.0 --depth 1 https://github.com/raspberrypi/pico-sdk.git /path/to/pico-sdk
git -C /path/to/pico-sdk submodule update --init
cmake -S lightman/firmware -B lightman/build/pico \
  -DPICO_SDK_PATH=/path/to/pico-sdk -DCMAKE_BUILD_TYPE=Release
cmake --build lightman/build/pico -j
```

Hold BOOTSEL while connecting the Pico over USB, then copy
`lightman/build/pico/lightman.uf2` to the `RPI-RP2` drive. BOOTSEL flashing works
independently of USB support in the application. UART/USB debug stdio are
both disabled so debug text cannot pollute the serial terminal connection.
The board/layout target is the original 2 MiB Pico, not Pico 2 or Pico W.

## Wiring

| Function | GPIO |
| --- | --- |
| UART TX / RX | 0 / 1 |
| CTS / RTS | 2 / 3 |
| DTR / DSR | 4 / 5 |
| PS/2 clock / data | 6 / 7 |
| VGA HSYNC / VSYNC | 16 / 17 |
| VGA red / green / blue | 18 / 19 / 20 |

See [wiring and electrical interfaces](docs/wiring.md) before connecting the
board. One MAX3232 supports TX/RX plus RTS/CTS when wired; a second adds DTR/DSR.
DCD/RI are not implemented. KiCad design files have not been changed to match
these assignments.

## Setup

Defaults are **9600 baud, 8N1, no flow control, VT100, local echo off, DEL
Backspace, Regular font, white text**. Press **F12** to open setup.

- Up/Down selects a setting; Left/Right or Space changes it.
- Enter applies settings for this session.
- S applies and saves settings to flash.
- Esc or F12 cancels the draft changes.
- The last menu row restores factory defaults to the draft; apply/save it
  using Enter/S. Terminal mode changes clear the terminal screen.

Choose 300–115200 baud, 7/8 data bits, parity, stop bits, flow control, terminal
mode, echo, Backspace behavior, Regular/Bold font, and white/green/yellow text.
The menu shows UART errors, dropped TX/PS/2 data, missed VGA deadlines and DSR.
Incoming host text continues updating a separate terminal screen during setup.

Pause the host before changing serial framing or saving. Flash saves briefly
blank VGA and suspend interrupt handling. Two checksummed flash records protect
against an interrupted save; normal UF2 updates preserve saved settings.

## Fonts

Both fonts are compiled into firmware and selected at runtime. Developers can
replace the build-time inputs using `LIGHTMAN_REGULAR_FONT` and
`LIGHTMAN_BOLD_FONT`. See [font assets, format and licensing](assets/fonts/README.md).

## Tests

Portable tests do not require the Pico SDK:

```sh
cmake -S lightman/firmware -B lightman/build/host \
  -DLIGHTMAN_HOST_TESTS=ON -DCMAKE_BUILD_TYPE=Debug
cmake --build lightman/build/host -j
ctest --test-dir lightman/build/host --output-on-failure
```

Tests cover terminal positioning/scrolling/modes/replies, malformed streams,
keyboard sequences, PS/2 frame parity and timeout, settings validation/CRC,
and generated font data. A seeded 250,000-byte malformed-input exercise checks
cursor bounds. For sanitizer checks add
`-DCMAKE_CXX_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer"` to a
separate host build directory. See [hardware acceptance checks](tests/bringup.md)
for the remaining bench work.

## Layout and architecture

- `firmware/src/terminal.cpp`, `keyboard.cpp`, `config.cpp`: portable core.
- `firmware/src/video.cpp`, `video.pio`: PIO/DMA VGA on core 1; core 0 renders
  packed glyph rasters into three buffers and publishes completed frames.
- `firmware/src/serial.cpp`, `ps2.cpp`: interrupt-driven input; bounded queues.
- `firmware/src/main.cpp`, `settings.cpp`: local setup and flash persistence.
- `firmware/boards/`: pin map; `assets/fonts/`: source fonts and license.
- `tests/`: portable tests and bench procedures; `tools/`: font converter.
- `hardware/`, `mechanical/`: carrier-board and enclosure designs.

Original source is under the repository [MIT license](../LICENSE). Embedded
font assets have their own SIL Open Font License. Dependencies are the official
[Pico SDK](https://github.com/raspberrypi/pico-sdk) and its build tools.
