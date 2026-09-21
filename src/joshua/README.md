# joshua

Joshua is a console development machine for IMNOTWOPR system software. It runs
W65C02 programs against configurable RAM, ROM, a W65C22 VIA, and a W65C51N ACIA.
Use your preferred external assembler/compiler to build firmware, load the binary,
and debug it in Joshua's monitor.

**Version 0.1 is an initial implementation, not yet a fully validated hardware
replacement.** The CPU performs individual bus accesses and advances peripherals
on every cycle. Its instruction behavior has substantial independent test coverage.
Peripheral coverage and interrupt/pin timing are still incomplete; see
[accuracy and validation](docs/accuracy.md) before using it to verify hardware timing.

## Build and try it

Requirements: a C++23-capable GCC toolchain and CMake 3.24 or newer. There are no
third-party runtime dependencies. Python 3 is optional for integration tests and
the external instruction-vector runner.

On Linux, from this directory:

```sh
cmake --preset gcc14
cmake --build --preset gcc14 -j
ctest --preset gcc14
./build/gcc14/joshua --profile profiles/echo.profile --run
```

The included ROM prints `>` and immediately echoes each typed character through
the emulated ACIA. Those visible characters are the guest's echo; Enter does not
repeat the whole line. The demo expands Enter (CR) to CR/LF to advance to the next
line. It leaves other bytes unchanged, so send CR alone for a newline when using
this demo with scripted input. This conversion belongs to the demo firmware;
the serial transport itself passes bytes unchanged.

Press **Ctrl-]** to enter the monitor; enter **`run`** to return to the serial
console. In serial mode Ctrl-C is delivered to the guest. `quit` exits the monitor.

On Windows, use a native console launched from an **MSYS2 UCRT64** environment
with GCC, CMake and Ninja available:

```sh
cmake --preset ucrt64
cmake --build --preset ucrt64
ctest --preset ucrt64
./build/ucrt64/joshua.exe --profile profiles/echo.profile --run
```

The Windows console implementation is included but has not been run on Windows
yet. Windows Terminal or a native console is required for direct key input;
MSYS/mintty pipes use the batch-monitor behavior. Native Windows console testing
is an outstanding validation task.

The `default` preset uses the active C++ compiler. `release` provides an optimized
build, useful for large test ROMs and `--unthrottled` runs. All presets require
C++23; none silently falls back to an older language standard.

## Machine configuration

The starting profile is deliberately generic:

| Component | Addresses | Notes |
| --- | --- | --- |
| RAM | `$0000–$7FFF` | 32 KiB, initially zero |
| VIA | `$8000–$800F` | 16 registers |
| ACIA | `$8010–$8013` | Data, status/reset, command, control |
| Unmapped | `$8014–$BFFF` | Reads return `$FF`; writes are ignored |
| ROM | `$C000–$FFFF` | 16 KiB, initially `$FF` |

CPU clock defaults to 1 MHz. Reset reads `$FFFC/$FFFD`; NMI and IRQ/BRK use their
normal vectors. An empty ROM has no useful boot program. Supply an image or use
the monitor to load/assemble code and set PC.

Profiles are small text files, with one `key = value` entry per line:

```ini
clock-hz = 1000000
ram = $0000:$8000
via = $8000
acia = $8010
rom = $C000:$4000:firmware.bin
escape = $1D
```

Blank lines and whole-line `#` or `;` comments are allowed. Paths in profiles are
relative to the profile's directory. Image paths can contain spaces and may be
quoted. Paths passed on the command line are relative to the working directory.

RAM/ROM entries use `BASE:SIZE[:IMAGE]`. Repeat them for multiple regions. The first
entry for a type replaces that type's default regions. Images start at the region's
base; shorter images leave the remaining bytes at the RAM/ROM fill value. Images
larger than the region are rejected. Use `none` to omit a component. Maps that
overlap, are empty, or extend beyond `$FFFF` are rejected.

Command-line overrides take precedence regardless of where `--profile` appears:

```sh
./build/gcc14/joshua --profile profiles/default.profile --rom '$C000:$4000:firmware.bin'
./build/gcc14/joshua --ram 0:10000 --rom none --via none --acia none
```

Quote `$` on shells that expand it, or omit the prefix. Addresses, sizes and monitor
counts default to hexadecimal. `$` or `0x` explicitly selects hex; `0d`, `0o`, and
`0b` select decimal, octal, and binary. `clock-hz` and CLI `--cycles` default to
decimal. Leading zeroes alone do not change the default base.

`--pc ADDRESS` overrides PC after reset. `--escape 1C` chooses Ctrl-\ instead.
The escape byte is intercepted immediately; use monitor `send 1D` when the guest
needs a literal Ctrl-]. `--help` lists all options.

## Monitor

Joshua starts paused unless `--run` is specified. CPU status appears above each
interactive prompt. Memory views show hexadecimal bytes and printable ASCII.

```text
mem C000 40
dis C000 10
asm 0200 LDA #$41
asm 0202 STA $8010
write 0205 EA EA
regs pc 0200
step
trace 2
break C020
run C000
```

| Command | Operation |
| --- | --- |
| `mem ADDRESS [COUNT]` | Inspect bytes without device side effects |
| `write ADDRESS BYTE ...` | Patch RAM or ROM |
| `dis ADDRESS [COUNT]` | Disassemble instructions |
| `asm ADDRESS INSTRUCTION` | Assemble one instruction and report the next address |
| `regs [REGISTER VALUE]` | Inspect/edit PC, A, X, Y, SP, P |
| `break [ADDRESS]` | List/add execution breakpoints |
| `break enable\|disable\|delete ADDRESS` | Change a breakpoint |
| `break move OLD NEW` | Move a breakpoint, preserving its enabled state |
| `step [COUNT]` | Step instructions; an idle WAI step advances one cycle |
| `trace [COUNT]` | Step with individual bus reads/writes and SYNC output |
| `run [ADDRESS]` | Resume execution and serial communication |
| `load FILE ADDRESS` | Load a raw binary |
| `save FILE ADDRESS COUNT` | Save a raw binary, replacing the named file |
| `map` | Show the machine's configured mappings |
| `io read ADDRESS` | Read through the real bus, including register side effects |
| `io write ADDRESS BYTE` | Write through the real bus |
| `send BYTE ...` | Queue received serial bytes |
| `reset` / `nmi` | Reset CPU/peripherals or latch an NMI |
| `help` / `quit` | Command help or exit |

Short forms include `m`, `w`, `d`, `a`, `r`, `b`, `s`, `g`, `c`, `q`, and `?`.
`deposit` and `deposite` alias `write`. Commands accept `;` comments; quote filenames
containing spaces. Instruction mnemonics are case insensitive.

The assembler supports the documented W65C02 instruction set, numeric operands,
all addressing modes, and `.byte`. Four-digit `$` operands force absolute
addressing: `LDA $0012` differs from `LDA $12`. Branch operands are destination
addresses and must be in range. There are no labels, expressions, macros, object
files or project builds inside the monitor. Reserved NOP encodings disassemble as
`.BYTE` so the actual bytes remain visible and round-trip correctly.

Debugger patches bypass ROM protection but cannot target I/O or unmapped memory.
The entire input/range is validated before any bytes are changed. CPU writes still
obey ROM protection. Inspection, disassembly, and saving never consume serial data
or clear interrupt flags. `io` explicitly performs a bus transaction and advances
the machine by one cycle.

Breakpoints stop before instruction execution and do not patch guest memory.
Continuing from a hit executes past that breakpoint once; a later visit stops
again. Reset retains loaded memory and breakpoints. STP requires reset; changing
PC alone does not restart a stopped CPU.

## Serial I/O and automation

The ACIA connects to the host terminal as a byte stream. Completed serial output
goes to stdout; monitor output and diagnostics go to stderr. Host input is queued,
then delivered over emulated frame durations. The model uses a fixed 1.8432 MHz
ACIA clock source. This is a virtual serial endpoint, not a connection to a host
`/dev/tty*` or COM port.

The W65C51N model has its hardware's always-set TDRE bit: polling bit 4 is **not** a
safe way to wait for transmission. Writing too soon replaces the ongoing byte.
The demo uses a firmware delay for 1 MHz / 19200 baud and is intended for typing,
not as a production interrupt-buffered serial driver. Sustained pasted input can
overrun a polling guest exactly as an unbuffered serial receiver can.

In monitor mode the emulated clock is paused. In run mode host pacing attempts to
track `clock-hz`; `--unthrottled` changes host pacing, not emulated device time.
`--cycles N` limits each run, checked at instruction boundaries, so the last
instruction may take the count slightly beyond N.

```sh
./build/gcc14/joshua --profile profiles/echo.profile \
  --script examples/echo-smoke.mon --cycles 20000 --unthrottled > serial.log
```

This produces `>Hello` followed by CR/LF. `--script` disables live terminal input
and stops on the first command error with a nonzero exit code. Redirected stdin
also accepts monitor commands; it is not interpreted as a live serial stream.
Use `send` for deterministic scripted input. A scripted `run` needs a breakpoint,
STP, or a cycle limit to return to subsequent commands.

`examples/echo.mon` recreates the included ROM entirely through the ad-hoc monitor
assembler. Run it from this directory to regenerate `examples/echo.bin`.

## Development

See [architecture](docs/architecture.md) for ownership, timing boundaries and the
extension points, and [accuracy](docs/accuracy.md) for test evidence and remaining
work. Joshua is covered by the repository's MIT license, copied here so this
directory can also be built as a standalone project.
