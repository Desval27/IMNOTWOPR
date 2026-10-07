# Lightman baseline requirements

The initial firmware targets the original Raspberry Pi Pico (RP2040, 2 MiB
flash). See [platform](platform.md), [wiring](wiring.md), and
[compatibility](compatibility.md) for implementation details.

| Area | Selected baseline |
| --- | --- |
| Display | Fixed 640x480 at 60 Hz; 80x24 text centered vertically |
| VGA pins | HSYNC 13, VSYNC 14, R0..R2 15..17, G0..G2 18..20, B0..B1 21..22 |
| Color | RGB332 resistor DACs; channel 0 is most significant; amber normal text by default |
| Keyboard | PS/2 set 2 through level shifters; US layout; clock GPIO8, data GPIO9 |
| Serial | UART0 on GPIO0/1; three MAX3232s support all DTE male DE-9 signals |
| Optional handshaking | CTS/RTS on GPIO2/3, DTR/DSR on GPIO5/4 |
| Modem status | DSR on GPIO4, DCD on GPIO6, RI on GPIO7; live status in setup |
| Framing | 300–115200 baud, 7/8 bits, N/E/O parity, 1/2 stop bits |
| Flow | None, XON/XOFF or RTS/CTS; bounded RX/TX queues |
| Emulation | Documented VT100/VT52 subset, ASCII and DEC drawing characters |
| Setup | F12 local menu, session apply or persistent save; eight normal-color presets including Classic green, Amber and White |
| Fonts | Fixed Regular/Bold set; developer-replaceable 8x16 PSF inputs |
| Persistence | Two versioned CRC32 records in the last two flash sectors |
| Build | C++23, CMake, Pico C SDK; portable host tests |

US layout and DTE wiring were confirmed for this baseline. USB keyboard input,
modem management, and complete DEC conformance remain outside the current
implementation. Power, enclosure, connector footprints and PCB routing still
require hardware validation against the updated pin map.

Before declaring hardware support validated, complete the
[bring-up procedure](../tests/bringup.md), including VGA deadline monitoring
under sustained serial/keyboard load and settings-save recovery.
