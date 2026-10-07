# IMNOTWOPR BUS ASSIGNMENT #

The system bus uses a **96-pin DIN 41612 connector** which is broken out into three different rows.

|   PIN  |     a    |     b     |     c    |
| :----: | :------: | :-------: | :------: |
|    1   | +5V      | +5V       | +5VSB    |
|    2   | +5V      | GND       | GND      |
|    3   | +12V     | -12V      | +12V2    |
|    4   | A0       | #VALID    | #PSON    |
|    5   | A1       | PHI2      | PWROK    |
|    6   | A2       | #RW       | GND      |
|    7   | A3       | #RESET    | I2C_SCL  |
|    8   | A4       | #IRQ      | I2C_SDA  |
|    9   | A5       | #NMI      | SPI_SCK  |
|   10   | A6       | READY     | SPI_MOSI |
|   11   | A7       | BE        | SPI_MISO |
|   12   | A8       | SYNC      | GND      |
|   13   | A9       | VPB       | SPI_ID0  |
|   14   | A10      | MLB       | SPI_ID1  |
|   15   | A11      | VDA       | SPI_ID2  | 
|   16   | A12      | VPA       | SPI_ID3  |
|   17   | A13      | E         | #SPI_SEL |
|   18   | A14      | MX        | GND      |
|   19   | A15      | RESERVED  | #SERIRQ  |
|   20   | A16      | RESERVED  | #BUSREQ0 |
|   21   | A17      | RESERVED  | #BUSGNT0 |
|   22   | A18      | D0        | #BUSREQ1 |
|   23   | A19      | D1        | #BUSGNT1 |
|   24   | A20      | D2        | GND      |
|   25   | A21      | D3        | #BUSREQ2 |
|   26   | A22      | D4        | #BUSGNT2       |
|   27   | A23      | D5        | #BUSREQ3 |
|   28   | RESERVED | D6        | #BUSGNT3 |
|   29   | RESERVED | D7        | RESERVED |
|   30   | +12V     | -12V      | +12V2    |
|   31   | +5V      | GND       | GND      |
|   32   | +5V      | +5V       | GND      |


