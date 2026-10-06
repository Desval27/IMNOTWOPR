; IMNOTWOPR 
; System Diagnostics for the 6502-based computer system.

.segment "ZEROPAGE"
print_text_ptr:		.res	2
read_text_ptr:		.res	2

.segment "BSS"
input_buffer:		.res	256	; Line input, including its trailing NUL.
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

.segment "CODE"
reset:
	sei
	cld
	ldx	#$FF
	txs

	; Use the same serial setup as Ferrous: 19200 baud, 8-N-1, no IRQs.
	lda	#$1F
	sta	acia_ctrl
	lda	#$0B
	sta	acia_cmd
	stz	skip_lf

menu:
	lda	#<menu_text
	ldx	#>menu_text
	jsr	print_text
menu_prompt:
	lda	#<prompt
	ldx	#>prompt
	jsr	print_text
	lda	#<input_buffer
	ldx	#>input_buffer
	jsr	read_text

	; Require exactly one digit followed by Enter.
	cpy	#1
	bne	invalid_selection
	lda	input_buffer
	cmp	#'1'
	bcc	invalid_selection
	cmp	#('1' + MENU_COUNT)
	bcs	invalid_selection
	sec
	sbc	#'1'
	asl				; Two bytes per handler address.
	tax
	jsr	dispatch_option
	jmp	menu		; Each handler returns here with RTS.

invalid_selection:
	lda	#<invalid_message
	ldx	#>invalid_message
	jsr	print_text
	jmp	menu_prompt

dispatch_option:
	jmp	(option_handlers,x)	; 65C02 indexed indirect jump.

; Replace these stubs with diagnostics. Finish each handler with RTS.
option_1:
	lda	#<option_1_text
	ldx	#>option_1_text
	jsr	print_text
	rts

option_2:
	lda	#<option_2_text
	ldx	#>option_2_text
	jsr	print_text
	rts

option_3:
	lda	#<option_3_text
	ldx	#>option_3_text
	jsr	print_text
	rts

option_4:
	lda	#<option_4_text
	ldx	#>option_4_text
	jsr	print_text
	rts

.include "print_text.inc"
.include "read_text.inc"	

.segment "RODATA"

; To add an option, add its handler, table entry and menu label.
; Single-digit selections support up to nine options.
option_handlers:
	.word	option_1, option_2, option_3, option_4
MENU_COUNT = (* - option_handlers) / 2
.assert MENU_COUNT >= 1 .and MENU_COUNT <= 9, error, "Menu requires 1..9 options"

menu_text:
	.byte	$0D, $0A
	.byte	"SYSTEM DIAGNOSTICS", $0D, $0A
	.byte	"1. Option 1", $0D, $0A
	.byte	"2. Option 2", $0D, $0A
	.byte	"3. Option 3", $0D, $0A
	.byte	"4. Option 4", $0D, $0A
	.byte   $0D, $0A,0
prompt:
	.asciiz	"Select an option and press Enter: "
invalid_message:
	.byte	"INVALID SELECTION", $0D, $0A, 0
option_1_text:
	.byte	"option 1", $0D, $0A, 0
option_2_text:
	.byte	"option 2", $0D, $0A, 0
option_3_text:
	.byte	"option 3", $0D, $0A, 0
option_4_text:
	.byte	"option 4", $0D, $0A, 0

.segment "VECTORS"
	.word	0			; NMI vector address
	.word	reset		; RESET vector address
	.word	0			; IRQ/BRK vector address
