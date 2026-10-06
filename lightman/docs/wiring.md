# Lightman prototype wiring

These assignments target the original 2 MiB Raspberry Pi Pico. Numbers below
are GPIO numbers, not physical header positions. Firmware assignments live in
[`lightman_pico.h`](../firmware/boards/lightman_pico.h). Existing KiCad files
have not been updated or checked against this proposed wiring.

| Signal | GPIO | Pico physical pin | Destination |
| --- | ---: | ---: | --- |
| UART0 TX | 0 | 1 | MAX3232 driver input -> DE-9 pin 3 |
| UART0 RX | 1 | 2 | MAX3232 receiver output <- DE-9 pin 2 |
| CTS | 2 | 4 | MAX3232 receiver output <- DE-9 pin 8 |
| RTS | 3 | 5 | MAX3232 driver input -> DE-9 pin 7 |
| DTR | 4 | 6 | MAX3232 driver input -> DE-9 pin 4 |
| DSR | 5 | 7 | MAX3232 receiver output <- DE-9 pin 6 |
| PS/2 clock | 6 | 9 | Open-drain level shifter <-> keyboard clock |
| PS/2 data | 7 | 10 | Open-drain level shifter <-> keyboard data |
| VGA HSYNC | 16 | 21 | VGA pin 13 |
| VGA VSYNC | 17 | 22 | VGA pin 14 |
| VGA red | 18 | 24 | Series resistor -> VGA pin 1 |
| VGA green | 19 | 25 | Series resistor -> VGA pin 2 |
| VGA blue | 20 | 26 | Series resistor -> VGA pin 3 |
| Common ground | GND | e.g. 3 | DE-9 pin 5, keyboard ground, VGA grounds |

## Serial

The male DE-9 is **DTE**: TX on pin 3, RX on pin 2. A DTE host such as a PC
normally needs a null-modem cable (TX/RX crossed; handshake signals crossed
appropriately if used). A DCE device uses a straight-through connection.

Suggested transceiver allocation:

| IC channel | Driver | Receiver |
| --- | --- | --- |
| U1 channel 1 | TX | RX |
| U1 channel 2 | RTS | CTS |
| U2 channel 1 | DTR | DSR |
| U2 channel 2 | Spare | Spare |

One MAX3232 supports TX/RX and, if wired, RTS/CTS. Two chips add DTR/DSR with
a driver and receiver spare. DCD (DE-9 pin 1) and RI (pin 9) are not implemented;
adding both requires two receiver channels, one of which can be the spare on
U2. Thus all DE-9 signals need one more receiver beyond two MAX3232s.
See the [MAX3232 datasheet](https://www.ti.com/lit/ds/symlink/max3232.pdf).

Use 3.3 V transceiver supplies so receiver outputs are safe for the Pico.
Fit the charge-pump capacitors specified for the particular part and supply.
Never connect RS-232 voltages directly to GPIO. RTS and DTR are asserted by a
low GPIO level, which the driver converts to positive RS-232 voltage. CTS and
DSR are asserted when their receiver outputs are low. DTR stays asserted;
DSR is informational in setup and does not gate transmission. With no handshake
wiring, select None or XON/XOFF flow control. CTS/DSR GPIOs have pull-ups.

## Keyboard

Standard PS/2 mini-DIN-6 signals are pin 1 data, pin 3 ground, pin 4 +5 V,
and pin 5 clock. Confirm the connector footprint's mating/solder-side numbering
before layout. Use level shifting suitable for open-drain signals and pull-ups
on both voltage domains. The Pico side must stay at 3.3 V. Budget a regulated
5 V keyboard supply and common ground; do not feed 5 V to Pico GPIO.

The initial driver receives the keyboard's default scan-code set 2 and does
not send commands. Use a native PS/2 keyboard that starts scanning in set 2.
Keyboard LEDs, host-controlled repeat settings and USB-only keyboards with a
passive PS/2 adapter are not supported. Clock and data remain inputs.

## VGA

GPIO16–20 must remain consecutive in HS, VS, R, G, B order for the PIO program.
Use approximately 270 ohms in series with each color output as a prototype
starting point: a 75-ohm monitor termination then gives about 0.72 V from 3.3 V.
Measure the resulting levels on the actual circuit. Sync is 3.3 V logic with
negative polarity; RGB is blanked during sync and porches. Connect VGA signal
grounds (including pins 5, 6, 7, 8 and 10) appropriately. VGA/DDC and EDID are
not implemented; this is a fixed timing source.

Timing is 640 visible + 16 front porch + 96 sync + 48 back porch = 800 pixels;
480 visible + 10 front porch + 2 sync + 33 back porch = 525 lines. At 25.2 MHz
this is 31.5 kHz horizontal and 60 Hz vertical. The 80x24 text image occupies
640x384 pixels, centered vertically. PIO0 uses one state machine and two DMA
channels; core 1 handles scanlines, while core 0 handles the terminal and input.
