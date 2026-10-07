# lightman

Lightman is a Raspberry Pi Pico (RP2040) serial terminal with RGB332 VGA output,
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
| DCD / RI | 6 / 7 |
| PS/2 clock / data | 8 / 9 |
| VGA HSYNC / VSYNC | 13 / 14 |
| VGA R0 / R1 / R2 | 15 / 16 / 17 |
| VGA G0 / G1 / G2 | 18 / 19 / 20 |
| VGA B0 / B1 | 21 / 22 |

See [wiring and electrical interfaces](docs/wiring.md) before connecting the
board. Three MAX3232s support all eight DE-9 signals: TX/RX, RTS/CTS, DTR/DSR,
and DCD/RI, with common ground on pin 5. DSR, DCD and RI are status inputs
displayed in setup; they do not gate serial traffic.
The VGA resistor DACs use channel 0 as the most significant bit; see the wiring
guide for resistor values and signal order.

## Setup

Defaults are **9600 baud, 8N1, no flow control, VT100, local echo off, DEL
Backspace, Regular font, amber normal text**. Press **F12** to open setup.

- Up/Down selects a setting; Left/Right or Space changes it.
- Enter applies settings for this session.
- S applies and saves settings to flash.
- Esc or F12 cancels the draft changes.
- The last menu row restores factory defaults to the draft; apply/save it
  using Enter/S. Terminal mode changes clear the terminal screen.

Choose 300–115200 baud, 7/8 data bits, parity, stop bits, flow control, terminal
mode, echo, Backspace behavior, Regular/Bold font, and **Normal color**:
White, Classic green, Yellow, Amber, Red, Blue, Cyan or Magenta. Color changes
preview immediately in setup; Enter applies, S saves, and Esc/F12 restores the
previous color. Normal color is the base foreground on black; bold, underline,
blink, reverse video and the cursor use the same color. ANSI color SGR remains
unsupported. Amber uses RGB332 levels R=7, G=4, B=0.
The menu shows UART errors, dropped TX/PS/2 data, missed VGA deadlines, and
live DSR, DCD and RI status.
Incoming host text continues updating a separate terminal screen during setup.

Pause the host before changing serial framing or saving. Flash saves briefly
blank VGA and suspend interrupt handling. Two checksummed flash records protect
against an interrupted save; normal UF2 updates preserve saved settings.
Existing saved White/Green/Yellow choices remain valid. Amber is the default
when no valid settings exist or when factory defaults are restored.

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
all normal-color presets and their persistence, RGB332 DAC bit mapping,
and generated font data. A seeded 250,000-byte malformed-input exercise checks
cursor bounds. For sanitizer checks add
`-DCMAKE_CXX_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer"` to a
separate host build directory. See [hardware acceptance checks](tests/bringup.md)
for the remaining bench work.

## Layout and architecture

- `firmware/src/terminal.cpp`, `keyboard.cpp`, `config.cpp`: portable core.
- `firmware/src/video.cpp`, `video.pio`: PIO/DMA VGA on core 1; core 0 renders
  packed glyph rasters into three buffers and publishes completed frames.
  `firmware/include/colors.h` defines the normal-color palette and DAC encoding.
- `firmware/src/serial.cpp`, `ps2.cpp`: interrupt-driven input; bounded queues.
- `firmware/src/main.cpp`, `settings.cpp`: local setup and flash persistence.
- `firmware/boards/`: pin map; `assets/fonts/`: source fonts and license.
- `tests/`: portable tests and bench procedures; `tools/`: font converter.
- `hardware/`, `mechanical/`: carrier-board and enclosure designs.

Original source is under the repository [MIT license](../LICENSE). Embedded
font assets have their own SIL Open Font License. Dependencies are the official
[Pico SDK](https://github.com/raspberrypi/pico-sdk) and its build tools.
