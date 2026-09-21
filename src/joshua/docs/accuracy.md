# Accuracy and validation

Status: initial implementation, validated on Linux on 2026-09-21. This file records
what was actually tested and where the emulation is incomplete. Passing
instruction tests does not establish complete electrical or peripheral accuracy.

## CPU evidence

The following independent test binaries reached their documented success loops:

| Test | Load / entry | Success PC |
| --- | --- | --- |
| Klaus Dormann 6502 functional test | `$0000` / `$0400` | `$3469` |
| Klaus Dormann 65C02 extended-opcode test | `$0000` / `$0400` | `$24F1` |

Upstream: [6502_65C02_functional_tests](https://github.com/Klaus2m5/6502_65C02_functional_tests),
revision `7954e2dbb49c469ea286070bf46cdd71aeb29e4b`. The test binaries were
downloaded outside the project and are not redistributed here. Their SHA-256s:

```text
6502_functional_test.bin
fa12bfc761e6f9057e4cc01a665a7b800ff01ae91f598af1e39a1201d01953fd
65C02_extended_opcodes_test.bin
10a2a07fa240666fa610c46accebe8d42b1000feef3aae619da15a8d152869b2
```

The [SingleStepTests WDC 65C02 vectors](https://github.com/SingleStepTests/65x02/tree/2f6980a2d95757486c7bee24355c360e40e2a224/wdc65c02/v1)
were run at revision `2f6980a2d95757486c7bee24355c360e40e2a224`: 254 files, 10,000
cases each. The runner compares all registers, expected memory and the address,
data and direction of every bus access.

- **2,530,000 cases passed** all comparisons, covering 253 opcode encodings.
- All **10,000 `$5C` cases matched functional state but failed bus timing** because
  the reference uses four cycles and Joshua uses the datasheet's eight cycles.
- The external data set does not cover WAI/STP. Local tests cover their basic
  entry, wait, NMI wakeup and reset behavior.

The `$5C` discrepancy is unresolved. The [WDC W65C02S datasheet](https://www.westerndesigncenter.com/documentation/w65c02s.pdf),
Table 7-1, specifies eight cycles. Joshua retains that count. Its filler read
addresses for this encoding have not been verified on IMNOTWOPR hardware. Do not
use reserved `$5C` for calibrated delays until the installed CPU is measured.
The external vector runner intentionally reports this mismatch as a failure; it
does not silently waive it.

The CPU includes the documented CMOS instructions and bit operations, decimal
ADC/SBC, page-cross timing, CMOS RMW bus accesses, fixed indirect JMP behavior,
stack operations, BRK/IRQ/NMI/reset, WAI, STP and reserved NOP lengths. Register and
memory tests include arbitrary decimal operands in the upstream vectors.

Remaining CPU work includes precise IRQ/NMI sampling windows, externally timed
reset, RDY stalls, SO/BE/VPB/MLB pin behavior, single-cycle suspension, WAI wake
latency, and physical-hardware comparison. Current IRQ/NMI decisions happen at
instruction boundaries. No pin-level cycle-accuracy claim is made.

## Peripheral coverage

| Device | Implemented | Remaining / simplified |
| --- | --- | --- |
| RAM/ROM | Arbitrary non-overlapping regions, protection, debugger patching, raw images | Aliases, overlays and bank switching |
| W65C22 | Port data/direction, T1 one-shot/free-run/PB7, T2 interval/PB6 pulse count, IFR/IER, read acknowledgements | Shift register operation, input latching, CA/CB handshakes, physical pin timing |
| W65C51N | Data/status/command/control, emulated frame durations, RX full/overrun/IRQ, always-set TDRE, premature TX overwrite | Bit-level framing/errors, echo, parity, TX break/IRQ, dynamic CTS/DCD/DSR and programmable reference clock |

VIA shift/input-latch activation and nonzero PCR modes currently raise an explicit
error. ACIA echo, parity enable, transmitter IRQ and break modes also raise an
error. VIA inputs default high and can be supplied through the core's port APIs;
there is no external hardware attached to those ports in the console application.

The UART assumes a 1.8432 MHz reference and connected modem lines. Frames have
5–8 data bits and the configured stop-bit duration. When the control register
selects the external receiver clock, the model assumes 115200 baud. Durations are
rounded up to an integer CPU cycle. Host bytes queue before transmission, but the
emulated receiver has a single data register and can overrun. These are explicit
byte-endpoint approximations, not an electrical RS-232 model.

References: the repository's [hardware datasheets](../../../doc/DataSheets),
[WDC VIA datasheet](https://www.westerndesigncenter.com/documentation/w65c22.pdf)
and [WDC ACIA datasheet](https://www.westerndesigncenter.com/wdc/documentation/w65c51n.pdf).

## Local regression tests

The CTest suite passes in GCC 14 Debug and GCC 13 Release builds, both in C++23
mode. It also passes with GCC 14 AddressSanitizer and UndefinedBehaviorSanitizer
(including leak checking, run outside the sandbox because LeakSanitizer does not
support process tracing). It covers:

- Reset and representative instruction/decimal/branch/RMW timing and bus traces.
- All 256 opcode encodings through assembly/disassembly round trips.
- ROM protection, unmapped reads, overlap/range rejection and atomic failed edits.
- VIA timer IRQs, free-run reloads and non-destructive inspection.
- ACIA receive, status acknowledgement, timed transmit and overwrite behavior.
- Monitor commands, breakpoint editing and resuming past an execution breakpoint.
- File round trips, relative profile images and CLI precedence in either order.
- Serial echo through the actual application.
- Linux pseudo-terminal entry/exit, Ctrl-C delivery and terminal restoration.

The Windows/UCRT64 build and native console behavior remain unverified on a
Windows host. The C++ core has no POSIX dependency; terminal implementations are
selected with `_WIN32`.

## Reproducing external tests

For either functional ROM, use an all-RAM machine. Example for the extended test,
with a locally downloaded binary:

```sh
./build/release/joshua --ram 0:10000:/path/65C02_extended_opcodes_test.bin \
  --rom none --via none --acia none --unthrottled --cycles 100000000
```

Then enter:

```text
break 24f1
run 400
regs
quit
```

The success stop must be `Breakpoint at $24F1`, not merely a cycle-limit stop. For
the base test, use `$3469` and a budget of 150000000 cycles. Test binaries and
success addresses are tied to the revision above.

For locally downloaded WDC JSON vectors:

```sh
python3 tests/check_vectors.py build/release/joshua_vectors /path/wdc65c02/v1/*.json
```

The expected current result is 253 passing files and the explicit `$5C` timing
failure described above. The build never downloads test data. The vector runner
uses only Python's standard library and the native C++ harness.
