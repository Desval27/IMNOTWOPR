# MEMORY CONFIGURATION

There is no fixed or official memory map.  Modules are encouraged to allow for flexible configuration.  However, there are possibilities.

```
High Memory +----------------------------------+ 0xFFFF
            |                                  |
ROM         | KERNAL ROM                       | 16k
            |                                  |
            +----------------------------------+ 0xE000
            |                                  |
ROM         | PROGRAM ROM                      | 16k
            |                                  |
            +----------------------------------+ 0xC000
I/O         | MEMORY MAPPED I/O                | 256b
            +----------------------------------+ 0xBF00
            |                                  |
            | THE VOID                         |
            |                                  |
            +----------------------------------+ 0x0600
            |                                  |
RAM         | KERNAL DATA                      | 1k   
            |                                  |
            +----------------------------------+ 0x0200
            |                                  |
RAM         | STACK                            | 256b
            |                                  |
            +----------------------------------+ 0x0100
            |                                  |
RAM         | ZERO PAGE                        | 256b
            |                                  |
Low Memory  +----------------------------------+ 0x0000
```
