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
|    3   | #RESET   | #BUSREQ   |
|    4   | PHI2     | #BUSGNT   |
|    5   | R#W      | A15       |
|    6   | #VALID   | A14       |
|    7   | #IRQ     | A13       |
|    8   | #NMI     | A12       |
|    9   | #OE      | A11       |
|   10   | #BANK0   | A10       |
|   11   | #BANK1   | A9        |
|   12   | #BANK2   | A8        |
|   13   | D7       | A7        |
|   14   | D6       | A6        |
|   15   | D5       | A5        |
|   16   | D4       | A4        |
|   17   | D3       | A3        |
|   18   | D2       | A2        |
|   19   | D1       | A1        |
|   20   | D0       | A0        |
|   21   | +12V     | -12V      |
|   22   | GND      | GND       |
