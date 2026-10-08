; IMNOTWOPR 
; System Diagnostics for the 6502-based computer system.

.import acia_init
.import print_text
.import print_chr
.import read_text
.import input_buffer

.segment "ZEROPAGE"
mem_test_addr:	.res	2	; Current address (little endian).

.segment "BSS"
mem_test_start:	.res	2	; Inclusive start/end, preserved by the loop.
mem_test_end:	.res	2
hex_value:	.res	2	; Scratch value used while parsing input.

.segment "PROGRAM_CODE"
reset:
	sei
	cld
	ldx	#$FF
	txs

	jsr	acia_init

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

; Finish each diagnostic handler with RTS to return to the menu.
do_mem_test:
	lda	#<mem_test_text
	ldx	#>mem_test_text
	jsr	print_text

mem_test_read_start:
	lda	#<prompt_start_text
	ldx	#>prompt_start_text
	jsr	print_text
	jsr	read_hex_address
	bcs	mem_test_read_start
	sta	mem_test_start
	stx	mem_test_start+1

mem_test_read_end:
	lda	#<prompt_end_text
	ldx	#>prompt_end_text
	jsr	print_text
	jsr	read_hex_address
	bcs	mem_test_read_end
	sta	mem_test_end
	stx	mem_test_end+1

	; Compare high bytes first, then low bytes when the high bytes match.
	cpx	mem_test_start+1
	bcc	mem_test_bad_range
	bne	mem_test_begin
	cmp	mem_test_start
	bcs	mem_test_begin
mem_test_bad_range:
	lda	#<invalid_range_text
	ldx	#>invalid_range_text
	jsr	print_text
	bra	mem_test_read_end

mem_test_begin:
	lda	mem_test_start
	sta	mem_test_addr
	lda	mem_test_start+1
	sta	mem_test_addr+1
	ldy #$00
mem_test_loop:
	; TODO: Test the byte at mem_test_addr here.
	; Preserve mem_test_addr and the start/end variables in the test body.
	lda #$A9
	sta (mem_test_addr),Y
	lda #$FF
	lda (mem_test_addr),y
	cmp #$A9
	bne mem_bad
	lda #'.'
	jmp mem_status
mem_bad:
	lda #'X'
mem_status:	
	jsr print_chr
	

	; Check before incrementing so an end address of FFFF cannot wrap.
	lda	mem_test_addr
	cmp	mem_test_end
	bne	mem_test_next
	lda	mem_test_addr+1
	cmp	mem_test_end+1
	beq	mem_test_done
mem_test_next:
	inc	mem_test_addr
	bne	mem_test_loop
	inc	mem_test_addr+1
	bra	mem_test_loop
mem_test_done:
	lda	#<done_text
	ldx	#>done_text
	jsr print_text
	rts

; Read 1..4 hexadecimal digits without a prefix. Returns C clear and
; A = low byte, X = high byte on success; prints an error and sets C on failure.
read_hex_address:
	lda	#<input_buffer
	ldx	#>input_buffer
	jsr	read_text
	jsr	parse_hex_address
	bcc	read_hex_address_done
	lda	#<invalid_address_text
	ldx	#>invalid_address_text
	jsr	print_text
	sec
read_hex_address_done:
	rts

; Parse input_buffer with Y = length. Accept 0-9, A-F and a-f only.
; Returns C clear, A/X = low/high bytes; C set for invalid input.
; Clobbers A, X, Y and hex_value. Callers store the result only on success.
parse_hex_address:
	cpy	#1
	bcc	parse_hex_invalid
	cpy	#5
	bcs	parse_hex_invalid
	stz	hex_value
	stz	hex_value+1
	ldy	#0
parse_hex_digit:
	lda	input_buffer,y
	cmp	#'0'
	bcc	parse_hex_invalid
	cmp	#('9' + 1)
	bcc	parse_hex_decimal
	and	#$DF		; Convert lowercase ASCII letters to uppercase.
	cmp	#'A'
	bcc	parse_hex_invalid
	cmp	#('F' + 1)
	bcs	parse_hex_invalid
	sec
	sbc	#('A' - 10)
	bra	parse_hex_accumulate
parse_hex_decimal:
	sec
	sbc	#'0'
parse_hex_accumulate:
	ldx	#4
parse_hex_shift:
	asl	hex_value
	rol	hex_value+1
	dex
	bne	parse_hex_shift
	ora	hex_value
	sta	hex_value
	iny
	lda	input_buffer,y
	bne	parse_hex_digit
	lda	hex_value
	ldx	hex_value+1
	clc
	rts
parse_hex_invalid:
	sec
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

.segment "RODATA"

; To add an option, add its handler, table entry and menu label.
; Single-digit selections support up to nine options.
option_handlers:
	.word	do_mem_test, option_2, option_3, option_4
MENU_COUNT = (* - option_handlers) / 2
.assert MENU_COUNT >= 1 .and MENU_COUNT <= 9, error, "Menu requires 1..9 options"

menu_text:
	.byte	$0D, $0A
	.byte	"SYSTEM DIAGNOSTICS", $0D, $0A
	.byte	"1. MEMORY", $0D, $0A
	.byte	"2. VIA 2", $0D, $0A
	.byte	"3. ACIA", $0D, $0A
	.byte	"4. PSG", $0D, $0A
	.byte   $0D, $0A,0
prompt:
	.asciiz	"Select an option and press Enter: "
invalid_message:
	.byte	"INVALID SELECTION", $0D, $0A, 0
mem_test_text:
	.byte	"MEMORY TEST", $0D, $0A, 0
option_2_text:
	.byte	"option 2", $0D, $0A, 0
option_3_text:
	.byte	"option 3", $0D, $0A, 0
option_4_text:
	.byte	"option 4", $0D, $0A, 0

done_text:
	.byte	$0D, $0A, "DONE", $0D, $0A,0
prompt_start_text:
	.byte	"START: ", 0
prompt_end_text:
	.byte	"END: ", 0
invalid_address_text:
	.byte	"ENTER 1-4 HEX DIGITS (NO PREFIX)", $0D, $0A, 0
invalid_range_text:
	.byte	"END MUST BE >= START", $0D, $0A, 0

.segment "VECTORS"
	.word	0			; NMI vector address
	.word	reset		; RESET vector address
	.word	0			; IRQ/BRK vector address
