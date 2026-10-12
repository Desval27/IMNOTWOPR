.import acia_init
.import read_text
.import input_buffer
.import print_text
.import print_newline

.segment "PROGRAM_CODE"
reset:
	sei				; Disable interrupts
	cld				; Clear decimal mode
	ldx	#$ff		; Set up stack pointer
	txs				;

;
; System Init
;
	; .. Init code goes here
	jsr acia_init

	cli				; Enable interrupts	

;
; Command Loop
;
; At the moment all UI is via the serial port.  
; Wait until a return key before prompting.
command_wait:
	lda #<input_buffer
	ldx #>input_buffer
	jsr read_text		; ignore away the results

command:
	lda #<prompt		; Issue prompt
	ldx #>prompt
	jsr print_text

	lda #<input_buffer	; Read Command
	ldx #>input_buffer
	jsr read_text

	;
	; Parse & Execute
	;

	;
	; Command not recognized or malformed
	;
	lda #<unrecognized_command
	ldx #>unrecognized_command
	jsr print_text
	lda #<input_buffer
	ldx #>input_buffer
	jsr print_text
	jsr print_newline

	jmp command			; Going for a loop

;login:
	;lda	#<login_prompt
	;ldx	#>login_prompt
	;jsr	print_text
	;lda	#<input_buffer
	;ldx	#>input_buffer
	;jsr	read_text
	;lda	#<input_buffer
	;sta	compare_text_left
	;lda	#>input_buffer
	;sta	compare_text_left+1
	;lda	#<login_name
	;sta	compare_text_right
	;lda	#>login_name
	;sta	compare_text_right+1
	;jsr	compare_text
	;beq	login_accepted
;login_denied:
	;lda	#<denied_message
	;ldx	#>denied_message
	;jsr	print_text
	;bra	login
;login_accepted:
	;lda	#<greeting
	;ldx	#>greeting
	;jsr	print_text
;
;loop:
	;lda	#<prompt
	;ldx	#>prompt
	;jsr	print_text
	;lda	#<input_buffer
	;ldx	#>input_buffer
	;jsr	read_text	; Y is the number of characters entered.
;print_reverse_loop:
	;cpy	#0
	;beq	print_reverse_done
	;dey
	;lda	input_buffer,y
	;jsr	print_chr
	;bra	print_reverse_loop
;print_reverse_done:
	;jsr	print_newline
	;bra	loop
;
.segment "RODATA"

; The Makefile enables ca65's string_escapes feature.
;login_prompt:
	;.asciiz	"login: "
;login_name:
	;.asciiz	"joshua"
;denied_message:
	;.asciiz	"ACCESS DENIED.\r\n"
;greeting:
	;.asciiz	"GREETINGS PROFESSOR FALKEN.\r\n"
prompt:
	.asciiz	"what? "
unrecognized_command:
	.asciiz "unrecognized command "

.segment "VECTORS"
	.word	0			; NMI vector address
	.word	reset		; RESET vector address
	.word	0			; IRQ/BRK vector address
