; IMNOTWOPR 
; Common Kernal code for the 6502-based computer system.

.segment "ZEROPAGE"
print_text_ptr:		.res	2
read_text_ptr:		.res	2
compare_text_left:	.res	2
compare_text_right:	.res	2

i2c_ptr:            .res	2		; 2-byte pointer to RAM buffer
i2c_len:			.res	1		; Transfer count 1..255; zero returns error
i2c_addr:			.res	1		; 7-bit target address
i2c_reg:			.res	1		; Target register / sub-address
i2c_scan_addr:      .res    1		; Current 7-bit address being probed ($08..$77)

.segment "KERNAL_BSS"
input_buffer:		.res	256	; Up to 255 characters followed by NUL.
skip_lf:			.res	1	; Suppress the LF half of a CR/LF pair.
i2c_scan_callback:   .res 2	; Private callback for the current scan.

.segment "VIA"
via_portb:			.res	1
via_porta:			.res	1
via_ddrb:			.res	1
via_ddra:			.res	1
via_acr = via_portb + $0B

.segment "ACIA"
acia_data:			.res	1
acia_status:		.res	1
acia_cmd:			.res	1
acia_ctrl:			.res	1

.exportzp compare_text_left
.exportzp compare_text_right
.exportzp i2c_ptr, i2c_len, i2c_addr, i2c_reg

.export acia_init
.export acia_data, acia_status, acia_cmd
.export print_text
.export print_newline
.export print_chr
.export read_text
.export input_buffer
.export compare_text
.export i2c_init, i2c_start, i2c_stop
.export i2c_write_byte, i2c_read_byte
.export i2c_write_reg, i2c_read_reg, i2c_scan_bus

.segment "KERNAL_CODE"

acia_init:
    ; This clobbers A
	; Use the same serial setup as Ferrous: 19200 baud, 8-N-1, no IRQs.
	lda	#$1F
	sta	acia_ctrl
	lda	#$0B
	sta	acia_cmd
	stz	skip_lf
    rts

.include "i2c.inc"
.include "print_text.inc"
.include "read_text.inc"
.include "compare_text.inc"
