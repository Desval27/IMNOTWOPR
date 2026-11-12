# IMNOTWOPR CARTRIDGE PIN ASSIGNMENT #

WIP

The cartridge connector uses a 22 pin edge connector similar to the C64.  However, it is **NOT** compatible and will possibly cause bad things to happen if an incompatible cartridge is plugged in.  

~~**64 pin edge connector** with a pitch of 0.100"/2.54mm~~ <- This just wouldn't fit very well ;)

The cartridge connector only exposes part of the main system bus and is limited to the 16-bit address lines (A0..A15).  

**#** indicates **asserted low**

|   PIN  |     a    |     b     |
| :----: | :------: | :-------: |
|    1   | GND      | GND       |
|    2   | +5V      | +5V       |
|    3   | D7       | #BUSREQ   |
|    4   | D6       | #BUSGNT   |
|    5   | D5       | A15       |
|    6   | D4       | A14       |
|    7   | D3       | A13       |
|    8   | D2       | A12       |
|    9   | D1       | A11       |
|   10   | D0       | A10       |
|   11   | #RESET   | A9        |
|   12   | PHI2     | A8        |
|   13   | R#W      | A7        |
|   14   | #VALID   | A6        |
|   15   | #IRQ     | A5        |
|   16   | #NMI     | A4        |
|   17   | #OE      | A3        |
|   18   | #BANK0   | A2        |
|   19   | #BANK1   | A1        |
|   20   | #BANK2   | A0        |
|   21   | +12V     | -12V      |
|   22   | GND      | GND       |
