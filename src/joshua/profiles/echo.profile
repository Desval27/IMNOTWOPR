# Image paths are relative to this profile, not the working directory.
clock-hz = 1000000
ram = $0000:$8000
via = $8000
acia = $8010
serial-baud = 19200
serial-data-bits = 8
serial-parity = none
serial-stop-bits = 1
console-newline = raw
rom = $C000:$4000:../examples/echo.bin
