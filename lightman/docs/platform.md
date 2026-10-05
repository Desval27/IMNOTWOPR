# Pico platform decision

## Decision

Select the original Raspberry Pi Pico module, based on the RP2040 MCU, as the
platform for Lightman. This decision was made on 2026-10-05.

## Rationale

Lightman needs to generate a stable VGA display while receiving serial data,
processing keyboard input, and maintaining terminal state. The Pico provides
more room for these concurrent tasks than an ATmega328P-based design.

Raspberry Pi's scanvideo implementation uses PIO for video timing and DMA to
feed scanline data. This offers a starting point for VGA generation without
requiring the CPU to time every pixel. The firmware must still prepare display
data in time for output.

The Pico ecosystem also provides TinyUSB host examples, making USB keyboard
input a practical option alongside PS/2. Selecting the Pico does not yet select
the keyboard interface.

## Proposed starting architecture

The following is a design proposal to guide prototyping, not a set of finalized
requirements:

- Mount a socketed Pico module on a carrier PCB with the display, keyboard,
  serial, and power connectors.
- Use PIO and DMA for VGA output, starting with monochrome 640x480 video.
- Use an 8x16 bitmap font for an 80-column by 30-row text display.
- Store characters and attributes in a text buffer and render glyphs into
  scanline buffers.
- Use a hardware UART for communication with the serial host.
- Evaluate PS/2 for initial bring-up and native USB host for USB keyboards.

The surrounding circuitry must account for the Pico's 3.3 V GPIO, the chosen
serial electrical interface, and keyboard power and signal levels. USB host
use also needs a defined keyboard power supply and connector arrangement.

Pin assignments, video timing, buffer sizes, keyboard choice, terminal
compatibility, and the development toolchain remain open. Track these in
[requirements](requirements.md) as the prototype develops.

## References

- [Raspberry Pi Pico documentation](https://www.raspberrypi.com/documentation/microcontrollers/pico-series.html)
- [Raspberry Pi scanvideo architecture](https://github.com/raspberrypi/pico-extras/blob/master/src/common/pico_scanvideo/README.adoc)
- [Raspberry Pi USB host examples](https://github.com/raspberrypi/pico-examples#usb-host)
