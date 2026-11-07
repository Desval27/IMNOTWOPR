# Building the ca65 conversion

Install the cc65 tools (`ca65` and `ld65`) and GNU make 4.3 or newer, then run
from this directory:

```sh
make
```

For assembly only, use `make assemble`, or invoke ca65 directly:

```sh
ca65 -g -l m6502.lst -o m6502.o m6502.s
```

The default configuration remains the original `REALIO=4` (Apple), with
`ROMSW=1`, `ADDPRC=1`, and `INTPRC=1`. It uses the original 6502 instruction set.
The Apple target is validated by assembly/link and byte/layout checks. The
additional IMNOTWOPR target below is also exercised by runtime tests in Joshua.

## IMNOTWOPR ROM (`REALIO=6`)

From this directory:

```sh
make imnotwopr
../joshua/build/gcc14/joshua --profile ../joshua/profiles/m6502.profile --run
```

This assembles `m6502.s` with `-D REALIO=6` and links with `imnotwopr.cfg`.
It produces `m6502-imnotwopr.bin`, a complete 16 KiB ROM image for `$C000–$FFFF`,
plus matching `.map` and `.lbl` files. It includes CPU vectors and the initial
low-memory image; no separate RAM image needs to be loaded. Reset copies the
initial data and writable BASIC routines from ROM to RAM, initializes serial,
and enters BASIC. A fresh boot reports **43519 BYTES FREE** and `OK`.

The map matches the Forth port, independently of Joshua's generic default map:

| Address | Use |
| --- | --- |
| `$0000–$00FF` | BASIC workspace and self-modifying routines |
| `$0100–$01FF` | Floating-point output buffer and CPU stack |
| `$0200–$0203` | BASIC input-buffer prefix |
| `$0204–$0253` | Line input buffer, including terminator |
| `$0400–$0506` | Serial receive queue and driver state |
| `$0600–$AFFF` | BASIC program, variables, arrays, and strings |
| `$B000–$B00F` | VIA, reserved and unused by BASIC |
| `$B010–$B013` | W65C51N ACIA |
| `$C000–$FFF9` | BASIC, platform support, RAM initialization image, padding |
| `$FFFA–$FFFF` | NMI, reset, and IRQ vectors |

`RAMLOC=$0600` contains the initial zero; program text starts at `$0601`.
The fixed exclusive RAM limit `$B000` prevents initialization from probing I/O.
The historical memory-size and terminal-width questions are skipped; width is
80 columns. All interpreter code and constants remain in ROM except for the
original writable routines in low memory.

Serial uses **19200 baud, 8 data bits, no parity, 1 stop bit**, with a 1 MHz CPU
and the ACIA's 1.8432 MHz clock. Like the Forth port, output uses a delay rather
than TDRE polling; the [W65C51N datasheet](https://www.westerndesigncenter.com/wdc/documentation/w65c51n.pdf)
describes its unbuffered transmitter. Receive interrupts provide a 255-byte
queue for type-ahead. The driver reports overflow or receive errors and discards
the rest of the damaged input line through its newline. There is no serial
flow control; pace large pastes.

- Type BASIC keywords in uppercase; strings retain their case.
- CR, LF, and CR/LF are accepted. Output already contains CR/LF.
- Backspace and Delete erase; Ctrl-U clears the input line.
- Input lines accept 79 characters. Excess characters ring the bell; this
  limit also keeps stored lines within the historical signed copy-loop bounds.
- Ctrl-C breaks a running program; `CONT` resumes it when BASIC permits.
- `GET` is nonblocking. `INPUT` and `GET` are program-only commands in this BASIC.
- Ctrl-] enters Joshua's monitor; `run` resumes the serial console.
- Disk/tape LOAD/SAVE and external channels are disabled for this target.

For example:

```basic
10 FOR I=1 TO 3
20 PRINT "HELLO ";I
30 NEXT I
RUN
```

`imnotwopr_config.inc` holds platform settings, and `imnotwopr.inc` holds startup,
serial I/O, line editing, and interrupt/vector support. `convert.py` inserts the
conditional hooks during regeneration; `ms_basic_1978.asm` stays untouched.

Run the emulator checks with:

```sh
make check-imnotwopr
# Or select a different Joshua executable:
make check-imnotwopr JOSHUA=/path/to/joshua
```

Nine runtime tests cover boot/vectors/RAM initialization, arithmetic and strings,
error recovery, stored programs/arrays/GOSUB, input and editing, Ctrl-C/CONT,
nonblocking GET, receive overflow, cold reset, and maximum-length line storage.
The port has been tested in Joshua, not on physical IMNOTWOPR hardware.

## Original Apple output

| File | Contents / address |
| --- | --- |
| `obj/m6502.o` | ca65 object file |
| `obj/m6502.lst` | Assembly listing, including emitted bytes |
| `m6502.bin` | BASIC code/data beginning at `$0800` |
| `m6502-lowram.bin` | Initial RAM data and writable routines beginning at `$0000` |
| `m6502.map` | Linked segment layout |
| `m6502.lbl` | Debug labels and addresses |

The default build emits 8,408 bytes at `$0800–$28D7` and 272 bytes at
`$0000–$010F`. The BASIC memory region ends before the original `RAMLOC=$2A00`.
The low-memory image includes the startup jump, `CHRGET`, and the floating-point
output buffer. The gaps introduced by the original `ORG` directives are padded
explicitly so file offsets match addresses. These are raw images without load
headers or reset vectors; the main binary alone is not a complete machine image.
The previous generic `$C000` linker layout did not match this source.

## Regeneration and checks

```sh
make regen       # regenerate m6502.s from ms_basic_1978.asm
make clean
make check       # build both targets and run six conversion/image checks
```

Python 3 is required for regeneration and checks. Ordinary `make` builds the
checked-in conversion directly. Regeneration overwrites `m6502.s`; changes to the
translation belong in `convert.py`. The original `ms_basic_1978.asm` is unchanged.
The converter is specific to this listing, not a general MACRO-10 translator.
Apple (`REALIO=4`) and IMNOTWOPR (`REALIO=6`) have build targets. Other platform
settings require an appropriate linker layout and are not validated. PDP-10
simulator instructions are explicitly unsupported.

The checks compare regenerated source, assemble small conversion examples, and
inspect the default build's layout, dispatch table, keyword/error encodings,
text concatenation, and floating-point constants. Runtime tests are separate
(`make check-imnotwopr`). Neither suite establishes byte-for-byte identity with a
historical binary. The Apple output was verified unchanged when adding REALIO=6.

## What broke in the earlier conversion

- MACRO-10 uses `<...>` for both expressions and blocks. Counting every `>` as
  `.endif` broke expressions and macro definitions, while inline conditionals
  lost their closing directives. The converter now tracks blocks separately
  from expressions and ignores punctuation in strings and comments.
- `COMMENT` blocks use both `*` and `%` delimiters. Both are handled.
- The math package switches to `RADIX 8`, then returns to decimal. The conversion
  now respects those switches and explicit `^O` / `^D` literals.
- Immediate, indexed, indirect-Y, and indirect-jump forms needed translation,
  including instructions on the same line as labels. Byte-sized immediates
  explicitly retain the low eight bits, including the original `-1` constants.
- Configuration values and the token/error counters are mutable and need `.set`.
  Macro-local labels need `.local`; the conditional `ROR` replacement needs a
  distinct macro name, and indexed macro arguments need braces.
- `DT` emits text without an implicit zero; `DC` sets bit 7 of the last
  character. `ADR` emits a little-endian word. The `XWD ^O1000,opcode` form emits
  only the opcode byte; the left half is cross-assembler metadata.
- `RESTORE` in the dispatch table refers to `RESTOR`, relying on MACRO-10's
  six-character symbol names. The conversion resolves that alias explicitly.

The [ca65 manual](https://cc65.github.io/doc/ca65.html) documents the target
assembler's expressions, numeric variables, macros, and segment directives.
