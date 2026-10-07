# Machine configuration for ferrous system diagnostics. All addresses and sizes are hexadecimal.

clock-hz = 1000000

ram = $0000:$8000
via = $B000
acia = $B010
rom = $C000:$4000:../../ferrous/sysdiag.bin

serial-baud = 19200
serial-data-bits = 8
serial-parity = none
serial-stop-bits = 1

console-newline = auto
escape = $1D
