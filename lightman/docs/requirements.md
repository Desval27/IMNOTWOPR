# Initial requirements

## Intended behavior

- Operate as a Raspberry Pi Pico (RP2040)-based serial dumb terminal for IMNOTWOPR.
- Render received serial text on a VGA monitor.
- Accept keyboard input through PS/2 or USB and transmit it to the serial host.
- Keep host applications on the connected computer.

## Selected platform

Use the original Raspberry Pi Pico with the RP2040 MCU. See the
[platform decision](platform.md) for the rationale and proposed architecture.
This selects the MCU board; the surrounding circuit and firmware are still
to be designed.

## Decisions to make

| Area | Open decision |
| --- | --- |
| Pico integration | Carrier PCB, mounting, pin assignments, peripheral allocation, and memory budget |
| VGA | Video timing, text dimensions, color depth, and font size |
| Keyboard | PS/2, USB host, or both; keyboard layout and key mapping |
| Serial connection | Logic-level UART versus RS-232, connector, voltage levels, and any transceiver |
| Serial settings | Baud rates, framing, buffering, and flow control |
| Terminal behavior | Character set, control characters, escape sequences, and compatibility target |
| User settings | Configuration interface, local echo, newline handling, and persistence |
| Power and mechanics | Power source, connector placement, enclosure, and mounting |
| Development | Language, SDK, build system, flashing, and debugging tools |

## Suggested bring-up sequence

1. Allocate Pico pins, peripherals, and memory; define power and interface circuits.
2. Produce a stable VGA test pattern and then a text display.
3. Receive serial text and render it on screen.
4. Read a keyboard and send keystrokes to the host.
5. Implement the selected terminal control behavior.
6. Validate sustained serial traffic, scrolling, and simultaneous keyboard input.

Record chosen values and the reasons for them in this directory as the design
develops. The platform is selected; the decisions in the table remain open.
No capabilities have been implemented yet.
