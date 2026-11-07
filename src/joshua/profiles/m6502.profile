# IMNOTWOPR Microsoft BASIC (REALIO=6). All addresses and sizes are hexadecimal.

clock-hz = 1000000

ram = $0000:$B000
via = $B000
acia = $B010
rom = $C000:$4000:../../BASIC-M6502/m6502-imnotwopr.bin

serial-baud = 19200
serial-data-bits = 8
serial-parity = none
serial-stop-bits = 1

console-newline = raw
escape = $1D
