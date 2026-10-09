# SCC PCB

System Control Card PCB

Status: ⚠Untested⚠

The SCC module provides power control, status indication, and manual bus reset for the IMNOTWOPR computer. It switches the ATX power supply through the backplane power-on signal and uses separate LEDs to indicate standby power and PSU power-good status, automatically extinguishing the standby LED when main power is enabled. The board also provides connections for monitoring the +5 V, +12 V, −12 V, and +12 V2 rails with voltage meters.

Additional info forthcoming.

The SCC module replaces the prior SCC module and corrects some of its defects.

## Documents

- [Schematic](SCC_schematic.pdf)
- [Assembly](SCC_assembly.pdf)
- [Bill of Materials](bom.csv)
- [Interactive Bill of Materials](ibom.html)

## Gerber To Order

- [Default](gerber_to_order/SCC_160.0x100.0mm_for_Default.zip)
- [Elecrow](gerber_to_order/SCC_160.0x100.0mm_for_Elecrow.zip)
- [FusionPCB](gerber_to_order/SCC_160.0x100.0mm_for_FusionPCB.zip)
- [JLCPCB](gerber_to_order/SCC_160.0x100.0mm_for_JLCPCB.zip)
- [PCBWay](gerber_to_order/SCC_160.0x100.0mm_for_PCBWay.zip)

## Rendered Images

### Top 3D

![PCB Top 3D Render](SCC_top_3d.png)

### Top

![PCB Top Render](SCC_top.png)

### Bottom

![PCB Bottom Render](SCC_bottom.png)
