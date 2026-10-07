# Lightman prototype wiring

These assignments target the original 2 MiB Raspberry Pi Pico. Numbers below
are GPIO numbers, not physical header positions. Firmware assignments live in
[`lightman_pico.h`](../firmware/boards/lightman_pico.h). The serial interface
uses three MAX3232s for the full DE-9 signal set. Check the PCB against these
assignments before assembly.

| Signal | GPIO | Pico physical pin | Destination |
| --- | ---: | ---: | --- |
| UART0 RX | 0 | 1 | MAX3232 receiver output <- DE-9 pin 2 |
| UART0 TX | 1 | 2 | MAX3232 driver input -> DE-9 pin 3 |
| RTS | 2 | 4 | MAX3232 driver input -> DE-9 pin 7 |
| CTS | 3 | 5 | MAX3232 receiver output <- DE-9 pin 8 |
| DSR | 4 | 6 | MAX3232 receiver output <- DE-9 pin 6 |
| DTR | 5 | 7 | MAX3232 driver input -> DE-9 pin 4 |
| DCD | 6 | 9 | MAX3232 receiver output <- DE-9 pin 1 |
| RI | 7 | 10 | MAX3232 receiver output <- DE-9 pin 9 |
| PS/2 clock | 8 | 11 | Open-drain level shifter <-> keyboard clock |
| PS/2 data | 9 | 12 | Open-drain level shifter <-> keyboard data |
| VGA HSYNC | 13 | 17 | VGA pin 13 |
| VGA VSYNC | 14 | 19 | VGA pin 14 |
| VGA R0 | 15 | 20 | 3-Bit DAC_R0 -> VGA pin 1 |
| VGA R1 | 16 | 21 | 3-Bit DAC_R1 -> VGA pin 1 |
| VGA R2 | 17 | 22 | 3-Bit DAC_R2 -> VGA pin 1 |
| VGA G0 | 18 | 24 | 3-Bit DAC_G0 -> VGA pin 2 |
| VGA G1 | 19 | 25 | 3-Bit DAC_G1 -> VGA pin 2 |
| VGA G2 | 20 | 26 | 3-Bit DAC_G2 -> VGA pin 2 |
| VGA B0 | 21 | 27 | 2-Bit DAC_B0 -> VGA pin 3 |
| VGA B1 | 22 | 29 | 2-Bit DAC_B1 -> VGA pin 3 |
| Common ground | GND | e.g. 3 | DE-9 pin 5, keyboard ground, VGA grounds |

## Serial

The male DE-9 is **DTE**: TX on pin 3, RX on pin 2. A DTE host such as a PC
normally needs a null-modem cable (TX/RX crossed; handshake signals crossed
appropriately if used). A DCE device uses a straight-through connection.

Schematic transceiver allocation:

| IC channel | Driver | Receiver |
| --- | --- | --- |
| U1 channel 1 | TX | RX |
| U1 channel 2 | RTS | CTS |
| U3 channel 1 | DTR | DSR |
| U3 channel 2 | Spare | Spare |
| U5 channel 1 | Spare | DCD |
| U5 channel 2 | Spare | RI |

Three MAX3232s provide the three drivers and five receivers needed for all
eight DE-9 signals. The third chip receives DCD (DE-9 pin 1) and RI (pin 9).
See the [MAX3232 datasheet](https://www.ti.com/lit/ds/symlink/max3232.pdf).

Use 3.3 V transceiver supplies so receiver outputs are safe for the Pico.
Fit the charge-pump capacitors specified for the particular part and supply.
Never connect RS-232 voltages directly to GPIO. RTS and DTR are asserted by a
low GPIO level, which the driver converts to positive RS-232 voltage. CTS,
DSR, DCD and RI are asserted when their receiver outputs are low. DTR stays
asserted; DSR, DCD and RI are informational in setup and do not gate serial
traffic. RI shows the current input level, not a latched ring event. With no
handshake wiring, select None or XON/XOFF flow control. CTS/DSR/DCD/RI GPIOs
have pull-ups.

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

GPIO13–22 must remain consecutive in HS, VS, R0, R1, R2, G0, G1, G2, B0, B1
order for the PIO program. RGB332 provides three red, three green and two blue
bits. The GPIO and physical-pin assignments above match the schematic netlist.
**In this schematic, R0/G0/B0 are the most significant channel bits**, not the
least significant: their smaller resistors give them the greatest weight.

Each GPIO feeds its own resistor, with the outputs summed at the VGA color pin:

| Channel | Most significant bit | Middle bit | Least significant bit |
| --- | --- | --- | --- |
| Red | R0: R4, 470 ohms | R1: R5, 1 kohm | R2: R6, 2.2 kohms |
| Green | G0: R7, 470 ohms | G1: R8, 1 kohm | G2: R9, 2.2 kohms |
| Blue | B0: R10, 390 ohms | — | B1: R11, 1 kohm |

These are the schematic's resistor values; do not use the previous single
270-ohm resistor per channel. With ideal 3.3 V GPIO drive and a 75-ohm monitor
termination, all bits high gives approximately 0.699 V on red/green and 0.696 V
on blue. The chosen resistor ratios approximate binary weights. Measure levels
and color balance on the actual circuit. Sync is 3.3 V logic with
negative polarity; RGB is blanked during sync and porches. Connect VGA signal
grounds (including pins 5, 6, 7, 8 and 10) appropriately. VGA/DDC and EDID are
not implemented; this is a fixed timing source.

Timing is 640 visible + 16 front porch + 96 sync + 48 back porch = 800 pixels;
480 visible + 10 front porch + 2 sync + 33 back porch = 525 lines. At 25.2 MHz
this is 31.5 kHz horizontal and 60 Hz vertical. The 80x24 text image occupies
640x384 pixels, centered vertically. PIO0 uses one state machine and two DMA
channels; core 1 handles scanlines, while core 0 handles the terminal and input.
Each DMA transfer is one 16-bit pixel: bits 0/1 are HS/VS, bits 2–9 are the
eight color GPIOs in the order above, and bits 10–15 are discarded. PIO still
uses five system-clock cycles per pixel at 126 MHz. Firmware converts standard
`RRRGGGBB` RGB332 values into this GPIO order.
