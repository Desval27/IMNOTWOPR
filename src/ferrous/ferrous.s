.segment "ZEROPAGE"
print_text_ptr:		.res	2
read_text_ptr:		.res	2
compare_text_left:	.res	2
compare_text_right:	.res	2

.segment "BSS"
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

.segment "CODE"
reset:
	sei				; Disable interrupts
	cld				; Clear decimal mode
	ldx	#$ff		; Set up stack pointer
	txs				;

	; ACIA Init
	lda	#$1F		; 8-N-1, 19200 baud
	sta	acia_ctrl

	lda	#$0B		; No parity, no echo, no interrupts.
	sta	acia_cmd
	stz	skip_lf		; RAM is not initialized by the reset vector.

login:
	lda	#<login_prompt
	ldx	#>login_prompt
	jsr	print_text
	lda	#<input_buffer
	ldx	#>input_buffer
	jsr	read_text
	lda	#<input_buffer
	sta	compare_text_left
	lda	#>input_buffer
	sta	compare_text_left+1
	lda	#<login_name
	sta	compare_text_right
	lda	#>login_name
	sta	compare_text_right+1
	jsr	compare_text
	beq	login_accepted
login_denied:
	lda	#<denied_message
	ldx	#>denied_message
	jsr	print_text
	bra	login
login_accepted:
	lda	#<greeting
	ldx	#>greeting
	jsr	print_text

loop:
	lda	#<prompt
	ldx	#>prompt
	jsr	print_text
	lda	#<input_buffer
	ldx	#>input_buffer
	jsr	read_text	; Y is the number of characters entered.
print_reverse_loop:
	cpy	#0
	beq	print_reverse_done
	dey
	lda	input_buffer,y
	jsr	print_chr
	bra	print_reverse_loop
print_reverse_done:
	jsr	print_newline
	bra	loop

.include "read_text.inc"
.include "print_text.inc"
.include "compare_text.inc"

.segment "RODATA"

; The Makefile enables ca65's string_escapes feature.
login_prompt:
	.asciiz	"login: "
login_name:
	.asciiz	"joshua"
denied_message:
	.asciiz	"ACCESS DENIED.\r\n"
greeting:
	.asciiz	"GREETINGS PROFESSOR FALKEN.\r\n"
prompt:
	.asciiz	"@ "

.segment "VECTORS"
	.word	0			; NMI vector address
	.word	reset		; RESET vector address
	.word	0			; IRQ/BRK vector address
