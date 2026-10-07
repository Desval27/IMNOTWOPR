; IMNOTWOPR 
; Common Kernal code for the 6502-based computer system.

.segment "ZEROPAGE"
print_text_ptr:		.res	2
read_text_ptr:		.res	2
compare_text_left:	.res	2
compare_text_right:	.res	2

.segment "KERNAL_BSS"
input_buffer:		.res	256	; Up to 255 characters followed by NUL.
skip_lf:			.res	1	; Suppress the LF half of a CR/LF pair.

.segment "VIA"
via_portb:			.res	1
via_porta:			.res	1
via_ddrb:			.res	1
via_ddra:			.res	1

.segment "ACIA"
acia_data:			.res	1
acia_status:		.res	1
acia_cmd:			.res	1
acia_ctrl:			.res	1

.exportzp compare_text_left
.exportzp compare_text_right

.export acia_init
.export print_text
.export print_newline
.export print_chr
.export read_text
.export input_buffer
.export compare_text

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

.include "print_text.inc"
.include "read_text.inc"
.include "compare_text.inc"
