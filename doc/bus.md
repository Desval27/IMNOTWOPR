# IMNOTWOPR BUS ASSIGNMENT #

The system bus uses a **96-pin DIN 41612 connector** which is broken out into three different rows.

|   PIN  |     a    |     b     |     c    |
| :----: | :------: | :-------: | :------: |
|    1   | +5V      | +5V       | +5VSB    |
|    2   | +5V      | GND       | GND      |
|    3   | +12V     | -12V      | +12V2    |
|    4   | A8       | A0        | #PSON    |
|    5   | A9       | A1        | PWROK    |
|    6   | A10      | A2        | GND      |
|    7   | A11      | A3        | #BUSREQ0 |
|    8   | A12      | A4        | #BUSREQ1 |
|    9   | A13      | A5        | #BUSREQ2 |
|   10   | A14      | A6        | #BUSREQ3 |
|   11   | A15      | A7        | #BUSREQ4 |
|   12   | A16      | #RESET    | GND      |
|   13   | A17      | #VALID    | #BUSGNT0 |
|   14   | A18      | PHI2      | #BUSGNT1 |
|   15   | A19      | R#W       | #BUSGNT2 |
|   16   | A20      | D0        | #BUSGNT3 |
|   17   | A21      | D1        | #BUSGNT4 |
|   18   | A22      | D2        | GND      |
|   19   | A23      | D3        | #BANK0   |
|   20   | #ABORT   | D4        | #BANK1   |
|   21   | VPA      | D5        | #BANK2   |
|   22   | VDA      | D6        | I2C_SCL  |
|   23   | E        | D7        | I2C_SDA  |
|   24   | MX       | #IRQ      | GND      |
|   25   | #HALT?   | #NMI      | READY    |
|   26   | #IRQ4    | #IRQ0     | SYNC     |
|   27   | #IRQ5    | #IRQ1     | #VP      |
|   28   | #IRQ6    | #IRQ2     | #ML      |
|   29   | #IRQ7    | #IRQ3     | BE       |
|   30   | +12V     | -12V      | +12V2    |
|   31   | +5V      | GND       | GND      |
|   32   | +5V      | +5V       | GND      |
