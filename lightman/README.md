# lightman

Lightman is an IMNOTWOPR subproject to build a Raspberry Pi Pico (RP2040)-based
serial dumb terminal with VGA display output and PS/2 or USB keyboard input.

The terminal will display data received from a serial host and send keyboard
input back to that host. The host runs the applications; Lightman handles the
display, keyboard, and terminal behavior.

## Status

Initial project structure only. No firmware or hardware design is implemented
yet. The Raspberry Pi Pico (RP2040) is the selected MCU board. The toolchain,
keyboard interface, and terminal compatibility target remain to be selected.

See the [Pico platform decision](docs/platform.md) for the rationale and proposed
starting architecture.

## Project layout

```text
lightman/
|-- docs/                  Requirements, architecture, and design decisions
|-- firmware/
|   |-- boards/            Board-specific pin maps and configuration
|   |-- include/           Firmware headers
|   `-- src/               Terminal, VGA, keyboard, and serial implementation
|-- hardware/
|   |-- bom/               Bills of materials
|   |-- pcb/               PCB layouts
|   `-- schematics/        Circuit schematics
|-- mechanical/            Enclosure, panel, and mounting designs
|-- assets/
|   `-- fonts/             Bitmap fonts and their license information
|-- tests/                 Firmware tests and hardware validation procedures
`-- tools/                 Development, asset conversion, and test utilities
```

Directories containing only `.gitkeep` are placeholders so Git preserves the
initial structure. Remove a placeholder when adding real files to its directory.

## Starting points

See [initial requirements and open decisions](docs/requirements.md) when
planning the hardware and firmware. Add build and flashing instructions here
once the toolchain is chosen.

Lightman is part of [IMNOTWOPR](../README.md) and uses the repository's
[license](../LICENSE). Record the source and license of any third-party assets
or dependencies alongside them.
