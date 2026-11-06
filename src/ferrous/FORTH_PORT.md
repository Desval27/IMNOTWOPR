# Forth port status

`make forth` uses `forth.cfg`. The image occupies `$C000–$FFFF`, with CPU
vectors reserved at `$FFFA–$FFFF`. Forth and the IMNOTWOPR support routines
share the remaining ROM; the support routines are linked by symbol, rather
than fixed at `$E000`. The other targets retain their own linker layouts.

The dictionary retains all 540 original named entries and their link
expressions. Of these, 195 entries now have a two-byte CFA pointing to the
shared `NO_C64` native handler. The unsupported groups include:

- C64 KERNAL file, channel, disk, cassette, and printer operations.
- IEC bus operations such as `TALK`, `LISTEN`, and `CIOUT`. These are C64
  peripheral-bus operations, not ACIA terminal I/O.
- VIC display, cursor, color, sprite, and screen-editor operations.
- SID sound operations, including the register-shadow and voice words.
- C64 ROM/RAM banking and the storage/cache operations that depend on it.
- C64-specific startup and memory-limit implementations.

The default `KEY`, `?TERMINAL`, `EMIT`, and `R/W` backends also report
`NO C64`; their public vector entries remain available for future replacement.
Generic arithmetic, memory operations, compiler/assembler support, the `SYS`
machine-code bridge, and generic bit-mask helpers remain in place.

The shared handler prints the existing counted `NO C64` message through the
IMNOTWOPR ACIA routines, resets the stacks, and stops at the existing `main`
idle loop. It does not return to the unsupported word or enter `QUIT`.
This is an interim trap: the normal `ERROR`/`QUIT` path still depends on the
unported terminal backends and would recurse when reporting their failure.
The message table's new entry is index 26, and `MESSAGE` now derives its
upper bound from the table size.

This build is not an interactive Forth system yet. Serial input/output
vectors, startup/user-area initialization, memory allocation, and interpreter
restart remain porting work. The remaining fixed Forth RAM addresses and RAM
vocabulary links have not been relocated by this change.

After building, exercise every dictionary stub through the Forth dispatcher
and check the legacy startup paths with:

```sh
python3 tests/forth_c64.py ../joshua/build/ucrt64/joshua.exe
```

Use the corresponding Joshua executable path for other build configurations.
