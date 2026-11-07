# WHOPPING FORTH for IMNOTWOPR

An interactive 16-bit Forth for the W65C02, based on Tom Zimmer's 64FORTH,
with an ACIA serial console and a ROM-resident dictionary. It boots to `ok>`,
interprets commands, compiles new definitions into RAM, and recovers from errors
through the serial shell.

**Current status:** the serial port runs in the [Joshua emulator](../joshua/README.md).
The eight port regression tests pass. C64-specific storage, graphics, sound,
and peripheral operations remain unavailable. Physical-board operation and the
full inherited word set have not been validated by these tests.

- [Build and run](#build-and-run)
- [Try it](#try-it)
- [Availability](#availability)
- [Console and restart behavior](#console-and-restart-behavior)
- [Saving a session in Joshua](#saving-a-session-in-joshua)
- [Memory layout](#memory-layout)
- [Validation](#validation)
- [Source guide](#source-guide)

## Build and run

The ROM requires Make and the cc65 tools `ca65` and `ld65`. From the repository
root:

```sh
make -C src/ferrous forth
```

This produces three files under `src/ferrous`:

| File | Purpose |
| --- | --- |
| `forth.bin` | 16 KiB ROM image for `$C000–$FFFF`, including CPU vectors |
| `forth.lbl` | Current symbol addresses for debugging |
| `forth.map` | Linker memory/segment report |

Build Joshua using its [build instructions](../joshua/README.md#build-and-try-it).
With the Linux GCC 14 build, launch Forth from the repository root:

```sh
./src/joshua/build/gcc14/joshua --profile src/joshua/profiles/forth.profile --run
```

For the Windows UCRT64 build, use `src/joshua/build/ucrt64/joshua.exe` with the
same profile. Use a native console for interactive input; see Joshua's platform
notes.

The [Forth profile](../joshua/profiles/forth.profile) selects a 1 MHz CPU and
**19200 baud, 8 data bits, no parity, 1 stop bit**. It also selects the port's RAM
and device addresses and loads `forth.bin`. Use this profile: Joshua's default
memory map places the I/O devices at different addresses.

Startup displays:

```text
WHOPPING FORTH
16-bit serial shell; Ctrl-C aborts.
ok>
```

## Try it

Type each line at `ok>` and press Enter. Numbers initially use decimal.

```forth
2 3 + .
: DOUBLE 2 * ;
7 DOUBLE .
0 VARIABLE N
42 N !
N @ .
```

The three printing expressions produce `5`, `14`, and `42`. This dialect's
`VARIABLE` consumes an initial value, hence `0 VARIABLE N`.

Useful starting words:

| Word or command | Purpose |
| --- | --- |
| `HELP` | Show examples and console controls |
| `WORDS` | List names in the current vocabulary; names may include unavailable C64 words |
| `.S` / `DEPTH` | Inspect the data stack / obtain its depth |
| `HEX` / `DECIMAL` | Change the numeric base |
| `: NAME ... ;` | Compile a new word in RAM |
| `THEN`, `NEGATE`, `RECURSE` | Additional convenience words in this port |
| `ABORT` | Clear execution state and return to the prompt, retaining completed definitions |
| `COLD` / `EMPTY` | Discard user definitions and restart with the built-in dictionary |

Word lookup normalizes input names to uppercase. The port follows its inherited
64FORTH/fig-Forth conventions; it does not claim ANS Forth compatibility.

## Availability

| Area | Current availability |
| --- | --- |
| Interactive interpreter and colon compiler | Implemented; arithmetic, new definitions, and restart retention are exercised in Joshua |
| Serial terminal | `KEY`, `?TERMINAL`, `EMIT`, `EXPECT`, and `QUERY` use the ACIA shell; receive interrupts feed a software queue |
| Startup and recovery | Cold initialization, warm restart, stack reset, error reporting, and rollback of an unfinished definition are implemented |
| RAM dictionary | Checked allocation, user variables, writable vocabulary descriptors, and the `EM` memory-limit variable are implemented |
| Core Forth words | Arithmetic, stack, memory, formatting, and compiler words are retained; the regression suite covers a subset |
| Assembler and inspection tools | The inherited assembler vocabulary, `SYS` bridge, tracer, and decompiler remain in the source; full behavior is not covered by the port tests |
| Disk, cassette, files, printer, and IEC bus | Unavailable; retained words report `NO C64` |
| VIC display, sprites, cursor, and screen editor | Unavailable; retained words report `NO C64` |
| SID sound, voice, and register operations | Unavailable; retained words report `NO C64` |
| C64 banking and dependent block/cache operations | Unavailable; the default `R/W` backend also reports `NO C64` |

The source retains **540 original named dictionary entries** and adds six words
in [`forth_words.inc`](lib/forth_words.inc): `THEN`, `NEGATE`, `RECURSE`, `WORDS`,
`HELP`, and `BYE`. **191 original entries** are explicit unsupported-word stubs.
An entry having a non-stub implementation does not establish that all of its
inherited dependencies work on IMNOTWOPR.

Examples of unavailable words include `BORDER`, `UPORT`, `OPEN`, `DISK`, `FILE`,
`LOAD`, `SAVE`, `TALK`, `LISTEN`, `CIOUT`, `EDIT`, `SPEDIT`, and `VOICE1`. Some are
in the `SYSTEM` or `EDITOR` vocabulary rather than the default `FORTH` vocabulary.
IEC bus words are separate from the working ACIA terminal interface.

An unsupported word returns to the interactive prompt:

```text
ok> BORDER

? NO C64
ok>
```

The shared handler resets execution state and rolls back an unfinished
definition. It does not resume the unsupported operation. Completed definitions
remain available. Error 26 is `NO C64`; subsequent messages cover stack overflow,
serial input overflow, return-stack overflow, break, division by zero, and input
that is too long. `MESSAGE` derives its bounds from the error table.

## Console and restart behavior

| Input or action | Behavior |
| --- | --- |
| Enter | Submit a line; CR, LF, and CR/LF are accepted |
| Backspace or Delete | Erase the previous input character |
| `ok>` | Interpreting input |
| `... ` | A definition is still being compiled |
| Ctrl-C | Request an abort; the shell reports `BREAK` and returns to the prompt |
| Ctrl-] in Joshua | Enter Joshua's monitor; `run` resumes the paused Forth session |
| `BYE` in Joshua | Execute W65C02 `STP`, returning control to the monitor |

`QUERY` accepts up to **127 characters per line**. Input beyond the limit is
reported as `INPUT TOO LONG` on submission. The receive queue holds up to 255
bytes; a large paste can overrun it. Send longer programs in manageable lines.

Warm startup and `ABORT` preserve completed RAM definitions. `COLD` initializes
the user area and serial state, resets the dictionary, and prints the banner.
`EMPTY` resets the dictionary and returns through `ABORT`. Definitions reside in
RAM and are not written back to the ROM image.

After `BYE`, Joshua's `run` alone cannot resume a stopped CPU. Use `reset` and
then `run` to cold-boot Forth, or restore a snapshot saved before `BYE`.

## Saving a session in Joshua

Joshua can preserve the complete emulated machine, including the RAM dictionary.
Press **Ctrl-]**, then enter these commands at the **Joshua monitor**:

```text
save-state "forth-session.jss"
run
```

To restore, launch Joshua with the same Forth profile, enter its monitor, and use:

```text
load-state "forth-session.jss"
run
```

Loading stays paused until `run`. A snapshot requires a matching memory map and
CPU clock. See [Joshua's snapshot documentation](../joshua/README.md#saving-and-restoring-a-session)
for the saved state and host-setting exclusions. These are emulator monitor
commands; the inherited Forth file/storage words remain unavailable.

## Memory layout

The [linker configuration](forth.cfg) and [Joshua profile](../joshua/profiles/forth.profile)
define this port's current layout. It is not a mandatory IMNOTWOPR hardware map.

| Address range | Use |
| --- | --- |
| `$0000–$00FF` | Zero-page Forth registers, data stack, and support pointers |
| `$0100–$01FF` | CPU/return stack |
| `$0200–$05FF` | Common support RAM |
| `$0600–$07FF` | Serial queue and shell state |
| `$0800–$0FFF` | Forth workspace, RAM vocabulary descriptors, user area, and terminal input buffer |
| `$1000–$AFFF` | 40 KiB dictionary region; checked allocation reserves 256 bytes for working space |
| `$B000–$B00F` | VIA |
| `$B010–$B013` | ACIA |
| `$C000–$FFF9` | Forth and common support code in ROM |
| `$FFFA–$FFFF` | NMI, RESET, and IRQ/BRK vectors |

Forth cells are 16 bits. The current fixed workspace addresses include vocabulary
storage at `$0840`, the user area at `$0940`, and terminal input at `$0B80`.
Moving the port requires reconciling those addresses as well as the linker and
emulator configurations. Common support routines are linked by symbol and share
the ROM; they are not fixed at `$E000`.

## Validation

From the repository root, with Joshua already built:

```sh
make -C src/ferrous forth
python3 src/ferrous/tests/forth_c64.py src/joshua/build/gcc14/joshua -v
```

Use the corresponding executable path for another Joshua build. The suite reads
`forth.bin` and `forth.lbl`, so rebuild after changing assembly sources.

As checked on **2026-11-07**, all **eight tests pass**. Coverage includes:

- ROM size, reset/interrupt vectors, error-table entries, and `MESSAGE` bounds.
- Every retained unsupported dictionary entry, plus the legacy `R/W` backend,
  with an empty stack and invalid user pointer; prompt recovery and subsequent
  arithmetic are checked.
- Cold entry points, warm preservation of compiled words, and cold removal of them.
- Blocking `KEY`, empty-queue `?TERMINAL`, and serial `EMIT`.
- Linked board I/O addresses and a source guard against direct C64 I/O accesses
  and KERNAL calls.

This is emulator validation. The source guard is not a proof about addresses
computed at runtime, and the suite does not validate every inherited word,
assembler/tracer feature, or physical ACIA/IRQ timing. Those remain further
validation work, along with replacing the unsupported device and storage backends.

## Source guide

| File | Role |
| --- | --- |
| [`forth.s`](forth.s) | Forth core, original dictionary, error messages, vocabulary templates, and CPU vectors |
| [`lib/forth_shell.inc`](lib/forth_shell.inc) | Serial IRQ/input queue, startup, recovery, line editing, and allocation checks |
| [`lib/forth_words.inc`](lib/forth_words.inc) | Added convenience words and `BYE` |
| [`kernal.s`](kernal.s) | Common IMNOTWOPR serial and support routines |
| [`forth.cfg`](forth.cfg) | Forth-specific linker layout |
| [`tests/forth_c64.py`](tests/forth_c64.py) | Port regression tests; the historical filename is retained |

Dictionary headers use `<word>_NFA`, sharing the established code-field stem
where available: `QSTAC_NFA` / `QSTAC` describe `?STACK`. `ASM_` and `EDITOR_`
distinguish names where needed; native branch targets and tables describe their
function. Use the generated `forth.lbl` for current addresses.

Historical manual excerpts and original-address comments remain in the assembly
source. They describe the original C64 implementation in places where this port
now substitutes a serial handler or an unsupported-word stub; the current code
and tests determine availability.
