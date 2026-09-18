# IMNOTWOPR

**IMNOTWOPR** — *Information Management Network Operating Terminal & Wargames Optimized Planning Rig* — is a DIY-friendly, expandable 6502-family computer inspired by the architecture, modularity, and front-panel experience of classic systems such as the IMSAI 8080, while deliberately avoiding strict historical reproduction.

The system combines the open, card-oriented philosophy of S-100 machines with a **3U Eurocard mechanical format and 96-pin DIN 41612 backplane**. The result is intended to be a machine that is visually engaging, electrically accessible, mechanically robust, easy to modify, and suitable for experimenting with hardware, operating systems, peripherals, and alternative CPU configurations.

At its core, IMNOTWOPR is an attempt to build the kind of expandable 6502 computer that might have existed if the modular backplane philosophy of early microcomputers had evolved around the 6502 family instead of the Intel 8080.

## Project Goals

The primary goals of IMNOTWOPR are:

* Build a real, hardware-based 6502-family computer rather than an emulated system.
* Use a passive backplane and independent plug-in cards for CPU, memory, I/O, storage, video, sound, and other functions.
* Preserve the hands-on experience of classic front-panel computers, including blinking status lights, switches, processor control, and direct memory examination.
* Keep the architecture open and experimental rather than enforcing a single fixed memory map or peripheral layout.
* Favor through-hole and DIP components where practical.
* Use modern components where they provide clear benefits without hiding the operation of the machine.
* Make the system easy to probe, understand, modify, repair, and extend.
* Support both the W65C02 and eventual W65C816 CPU cards without redesigning the backplane.
* Provide room for experimenting with custom operating systems, monitors, device drivers, and unconventional hardware.

Historical authenticity is not a primary goal. The machine should feel like a classic expandable microcomputer while benefiting from several decades of hindsight.

## Mechanical Architecture

IMNOTWOPR uses the **3U Eurocard format**, with typical cards measuring approximately:

```text
160 mm × 100 mm
```

Cards plug into a passive backplane using **96-pin DIN 41612 connectors**.

This provides several advantages over a traditional PCB-edge S-100 connector:

* standardized card cages and guides,
* robust and replaceable connectors,
* good contact reliability,
* straightforward board insertion and removal,
* readily available mechanical hardware,
* flexible signal and ground assignment,
* and compatibility with existing Eurocard prototyping practices.

The Eurocard format also encourages functional separation. Rather than placing the entire system on one large PCB, the computer can evolve as a collection of specialized cards.

Typical cards may include:

```text
CPU
Memory
System Controller
Serial I/O
VIA / Parallel I/O
Mass Storage
Video
Sound
Networking
RTC
ADC / DAC
Front Panel
Prototype / Experimenter
```

The passive backplane itself should contain as little active circuitry as practical.

## System Bus

The IMNOTWOPR bus is inspired conceptually by S-100, but is designed specifically for the 6502 family.

The initial system is expected to use a **W65C02S**, while the backplane is provisioned from the beginning for eventual use with the **W65C816S**.

The bus therefore provides:

```text
A0-A23       24-bit address bus
D0-D7         8-bit bidirectional data bus

PHI2          System bus clock
R/W           Read/write direction
VALID         Valid external bus cycle
SYNC          Opcode-fetch indication

/RESET
/IRQ
/NMI
RDY

VPB
MLB

VDA
VPA
E
MX
/ABORT
```

Not every CPU implementation is required to generate every signal directly. CPU cards may synthesize bus-level signals so peripheral cards see a consistent interface.

For example, a W65C816 CPU card can latch the processor's multiplexed bank-address byte locally and present normal dedicated `A16-A23` signals to the backplane.

This means ordinary memory and peripheral cards do not need to understand the internal bus peculiarities of the installed processor.

## Address Space

The physical backplane provides a full:

```text
24-bit address bus
```

allowing up to:

```text
16 MiB
```

of physical address space.

A basic W65C02 CPU card operates naturally within bank `$00`:

```text
$000000-$00FFFF
```

with `A16-A23` normally held low.

Future CPU cards may use those lines differently. A W65C816 card can expose its complete 24-bit native address space, while an experimental W65C02 card could implement bank switching or other extended-address mechanisms.

The backplane does **not** enforce a fixed system memory map.

There is no mandatory division between RAM, ROM, and I/O, and no permanently assigned global I/O region. Individual cards may decode whichever portions of the address bus are appropriate.

This allows the machine to support very different system configurations without changing the backplane itself.

## Memory-Mapped I/O

IMNOTWOPR follows the native 6502 model of **memory-mapped I/O**.

Peripheral devices occupy normal addresses within the processor's address space rather than using a separate I/O instruction space.

The bus therefore does not require traditional S-100-style signals such as:

```text
IOR
IOW
INP
OUT
```

A peripheral card generally needs only:

```text
Address
Data
R/W
PHI2
VALID
```

plus any interrupt or DMA-related signals it requires.

This keeps peripheral design closely aligned with normal 6502 conventions.

## Power

Unlike classic S-100 systems, IMNOTWOPR does not distribute unregulated voltages and require every card to contain its own primary regulator.

The backplane distributes regulated power directly:

```text
+5 V      Main digital supply
+12 V     Auxiliary supply
-12 V     Auxiliary supply
GND       Common ground
```

The **+5 V rail** is the primary system supply and is used by normal CPU, memory, and logic cards.

The ±12 V rails are optional auxiliary services intended for devices such as:

* analog circuitry,
* audio interfaces,
* ADC/DAC hardware,
* legacy serial interfaces,
* storage devices,
* experimental peripherals,
* or other hardware requiring additional rails.

A normal digital card should not require ±12 V.

Multiple DIN 41612 contacts are assigned in parallel for +5 V and ground in order to reduce connector resistance and distribute current across the backplane.

Cards may include local filtering, bulk capacitance, protection, and optional secondary regulators as required.

Modern 3.3 V devices should normally derive their supply locally from +5 V rather than making 3.3 V a mandatory system-wide backplane rail.

## Front Panel

A dedicated front-panel controller provides one of the defining features of IMNOTWOPR: a large, interactive display inspired by machines such as the IMSAI 8080.

The panel may include indicators for:

```text
A0-A23
D0-D7
R/W
PHI2
SYNC
IRQ
NMI
RESET
BUS STATE
```

along with physical toggle or push-button controls.

Planned operator functions include:

```text
RUN
STOP
SINGLE CYCLE
SINGLE INSTRUCTION
RESET
EXAMINE
EXAMINE NEXT
DEPOSIT
DEPOSIT NEXT
```

The front panel is not intended merely as decoration. It participates directly in system operation.

### Processor Control

The panel can request that the CPU halt through dedicated control signals.

A processor card handles the details of stopping its particular CPU safely and returns an acknowledgement when it has reached a stable halted state.

This keeps CPU-specific control logic on the CPU card rather than embedding assumptions about a specific processor into the front panel.

### Bus Arbitration

For functions such as `EXAMINE` and `DEPOSIT`, the front-panel controller can temporarily request ownership of the system bus.

The basic handshake is:

```text
/BUS_REQ
/BUS_ACK
```

Once ownership is granted, the CPU card removes its address, data, and control drivers from the bus.

The front-panel controller then becomes a temporary bus master and can perform memory reads and writes directly.

This allows classic front-panel operation without relying on the processor to execute monitor code.

## Clocking

`PHI2` is treated as a **system bus clock**, not merely a private CPU pin.

Halting the processor does not necessarily halt the system clock.

This makes it possible for the front panel and other bus masters to perform valid bus cycles while the processor is stopped.

The initial CPU card may provide the master clock source, although a future dedicated system-controller card could assume that responsibility.

Clock speed is intentionally not fixed by the backplane specification.

The system should be able to operate slowly enough for observation and experimentation while remaining capable of significantly higher speeds when appropriately designed cards are installed.

## Bus Arbitration and Expansion

IMNOTWOPR is designed with the possibility of multiple bus masters.

Potential bus masters may eventually include:

* the CPU,
* front-panel controller,
* DMA controller,
* video hardware,
* storage controller,
* diagnostic hardware,
* or other experimental cards.

A generic request/acknowledge mechanism is preferred over exposing CPU-specific signals directly.

For example:

```text
/BUS_REQ
/BUS_ACK
```

allows a CPU card to translate the generic bus request into whatever mechanism its particular processor requires.

This makes the backplane less dependent upon the details of the W65C02 or W65C816.

## 65C02 and 65C816 Compatibility

The first CPU implementation is expected to use the **W65C02S**.

For that configuration:

```text
A0-A15   CPU address
A16-A23  normally 0
D0-D7    CPU data
```

The backplane nevertheless carries all 24 address bits.

A future **W65C816S** CPU card can use:

```text
A0-A23
D0-D7
```

as a native 24-bit address / 8-bit data architecture.

Any multiplexing required by the processor is handled locally on the CPU card.

The intent is that most RAM, ROM, I/O, and peripheral cards designed for IMNOTWOPR should work with either CPU without modification.

## Component Philosophy

IMNOTWOPR intentionally favors components that remain approachable to hobbyists.

Preferred technologies include:

* W65C02S and W65C816S processors,
* 74HC / 74HCT-series logic,
* DIP SRAM,
* EEPROM or Flash devices,
* W65C22 VIA,
* UARTs and similar peripheral ICs,
* discrete transistors,
* socketed programmable logic where useful,
* and through-hole connectors and passive components.

Surface-mount components are not prohibited, but should not be required merely for convenience if a practical through-hole alternative exists.

Programmable logic such as GALs, CPLDs, or microcontrollers may be used where appropriate, but the core operation of the system should remain understandable without treating large programmable devices as black boxes.

## Open Architecture

One of the fundamental goals of IMNOTWOPR is to avoid defining unnecessary policy at the backplane level.

The system therefore does not require:

* a specific ROM monitor,
* a particular operating system,
* fixed RAM size,
* fixed peripheral addresses,
* a specific storage format,
* a mandatory video system,
* or a single standard machine configuration.

A minimal system might consist of:

```text
CPU
RAM
ROM
Serial I/O
```

while a larger system could contain:

```text
CPU
Multiple RAM cards
ROM / Flash
Serial interfaces
Parallel interfaces
Mass storage
Video
Audio
Networking
Front panel
RTC
ADC / DAC
Custom hardware
```

Both configurations are equally valid.

## Software

Software development is expected to be just as experimental as the hardware.

Possible software projects include:

* machine-language monitors,
* assemblers,
* BASIC interpreters,
* Forth systems,
* custom operating systems,
* multitasking experiments,
* filesystem development,
* device-driver frameworks,
* bootloaders,
* networking stacks,
* 65C816 native-mode software,
* and compatibility environments for existing 6502 software.

No particular software environment is considered canonical.

The machine should be capable of evolving alongside the software written for it.

## Initial Planned Cards

The first generation of the system will likely include some subset of the following:

### CPU Card

W65C02-based processor card providing:

* processor,
* clock generation,
* address and data buffering,
* interrupt handling,
* bus arbitration,
* halt/step support,
* and 24-bit bus adaptation.

### Memory Card

Configurable RAM and ROM/Flash with selectable address decoding.

### Serial Card

Basic terminal interface suitable for initial software development and debugging.

### Front-Panel Controller

Controls system operation and provides address/data/status indicators, processor control, and Examine/Deposit functionality.

### VIA / General I/O Card

One or more W65C22 devices providing:

* digital I/O,
* timers,
* handshake lines,
* interrupts,
* and general experimentation facilities.

### Prototype Card

A general-purpose experimenter board exposing the system bus and providing space for custom circuitry.

Future cards may include storage, video, audio, networking, RTC, ADC/DAC, and other experimental hardware.

## Design Philosophy

IMNOTWOPR is not intended to be the smallest, fastest, cheapest, or most integrated 6502 computer possible.

There are already much easier ways to build those.

Instead, the project deliberately values:

```text
Visibility
Modularity
Experimentation
Repairability
Understandability
Physical controls
Blinking lights
Too many circuit boards
```

over integration.

The machine should invite its owner to remove cards, attach probes, change memory maps, build strange peripherals, write questionable operating systems, single-step instructions from the front panel, and occasionally wonder why there are quite so many LEDs.

That is the point.

