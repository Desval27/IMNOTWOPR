# IMNOTWOPR BUS ASSIGNMENT #

The system bus uses a **96-pin DIN 41612 connector** which is broken out into three different rows.

|   PIN  |     a    |     b     |     c    |
| :----: | :------: | :-------: | :------: |
|    1   | +5V      | +5V       | +5VSB    |
|    2   | +5V      | GND       | GND      |
|    3   | +12V     | -12V      | +12V2    |
|    4   | A0       | D0        | #PSON    |
|    5   | A1       | D1        | PWROK    |
|    6   | A2       | D2        | GND      |
|    7   | A3       | D3        | I2C_SCL  |
|    8   | A4       | D4        | I2C_SDA  |
|    9   | A5       | D5        | SPI_SCK  |
|   10   | A6       | D6        | SPI_MOSI |
|   11   | A7       | D7        | SPI_MISO |
|   12   | A8       | PHI2      | GND      |
|   13   | A9       | #RW       | SPI_ID0  |
|   14   | A10      | VALID     | SPI_ID1  |
|   15   | A11      | #RESET    | SPI_ID2  | 
|   16   | A12      | #IRQ      | SPI_ID3  |
|   17   | A13      | #NMI      | #SPI_SEL |
|   18   | A14      | READY     | GND      |
|   19   | A15      | #HALT_REQ | #SERIRQ  |
|   20   | A16      | #HALT_ACK | RESERVED |
|   21   | A17      | #BUS_REQ  | RESERVED |
|   22   | A18      | #BUS_ACK  | RESERVED |
|   23   | A19      | #ABORT    | RESERVED |
|   24   | A20      | SYNC      | GND      |
|   25   | A21      | VPB       | E        |
|   26   | A22      | MLB       | MX       |
|   27   | A23      | VDA       | RESERVED |
|   28   | RESERVED | VPA       | RESERVED |
|   29   | RESERVED | RESERVED  | RESERVED |
|   30   | +12V     | -12V      | +12V2    |
|   31   | +5V      | GND       | GND      |
|   32   | +5V      | +5V       | GND      |


