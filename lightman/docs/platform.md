# Pico platform decision

The original Raspberry Pi Pico, based on RP2040, was selected on 2026-10-05.
Its two cores, PIO, DMA and hardware UART allow a fixed VGA signal while the
terminal processes serial input and keyboard events.

The firmware uses the Pico C SDK directly. PIO0 streams all ten consecutive
VGA GPIOs (13–22: HS, VS, R0..R2, G0..G2, B0..B1) from two DMA scanline buffers
at a 25.2 MHz pixel clock. Each pixel is a 16-bit DMA transfer: ten output bits
and six discarded bits, with a 16-bit PIO autopull threshold. The system
clock is 126 MHz; each PIO pixel takes five cycles. Core 1 expands pre-rendered
packed pixel rows and rearms alternating DMA channels. It does not parse text,
access flash font data, or block waiting for the terminal's frame publisher.

Core 0 owns terminal state, US PS/2 scan-code decoding, UART queues and setup.
It renders complete 640x384 monochrome rasters into a three-buffer pool, then
publishes an index under a short hardware spinlock. Core 1 adopts the latest
published raster at a frame boundary; the buffer it scans is never modified.
Three rasters cost about 90 KiB. Each frame also carries its normal-color
selection. Eight RGB332 presets expand glyph rows through a 32 KiB lookup
table; two 800-pixel halfword scanline buffers use 3,200 bytes. The raster stays
1 bit per pixel, with a single selected foreground and black background.
This leaves room in the RP2040's 264 KiB SRAM for fonts, terminal state, I/O
queues and stacks. Core 0 and
core 1 each reserve a 4 KiB stack. No RTOS or pico-extras dependency is needed.

Serial RX and PS/2 falling edges use core 0 interrupts. Queues keep interrupts
short and separate byte capture from parsing. UART0 CTS gates hardware TX;
RTS is a GPIO so it reflects the software RX queue rather than only the UART
FIFO. DTR remains asserted; DSR, DCD and RI are sampled and displayed in setup.

Saving settings stops VGA DMA and parks core 1 in an SRAM loop with interrupts
disabled. Core 0 then disables its interrupts for the SDK flash erase/program
calls, restores interrupts, verifies the write, and resumes VGA. The last two
4 KiB flash sectors are reserved by a linker assertion. See
[compatibility](compatibility.md) for the implications for uninterrupted serial
traffic during saves.

This design has been cross-compiled and its portable logic tested. Physical
VGA timing, analog levels and sustained-load timing margins still require the
[bench checks](../tests/bringup.md).

References: [Pico SDK hardware APIs](https://www.raspberrypi.com/documentation/pico-sdk/hardware.html),
[Pico-series documentation](https://www.raspberrypi.com/documentation/microcontrollers/pico-series.html).
