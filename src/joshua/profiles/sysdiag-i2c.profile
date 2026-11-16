# System diagnostics with three address-only I2C targets on PB7=SDA / PB6=SCL.
# Addresses and sizes are hexadecimal. Targets ACK write addresses only.

clock-hz = 1000000
ram = $0000:$8000
via = $B000
acia = $B010
rom = $C000:$4000:../../ferrous/sysdiag.bin

i2c-target = $3C
i2c-target = $50
i2c-target = $68

serial-baud = 19200
serial-data-bits = 8
serial-parity = none
serial-stop-bits = 1
console-newline = auto
escape = $1D
