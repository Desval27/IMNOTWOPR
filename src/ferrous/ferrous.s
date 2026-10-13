.import acia_init
.import read_text
.import input_buffer
.import print_text
.import print_newline
.import print_chr
.import compare_text
.importzp compare_text_left, compare_text_right

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
	jsr command_parse
	bcs command_malformed
	lda command_argc
	beq command		; Empty lines just prompt again.
	jsr command_execute
	bcc command

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

command_malformed:
	lda #<malformed_command
	ldx #>malformed_command
	jsr print_text
	jmp command

.include "command.inc"

; Example handler: print each parameter as a numbered item. With no parameters,
; echo prints a newline. print_text/print_chr preserve Y, our argument index.
command_echo:
	lda command_argc
	cmp #1
	bne command_echo_parameters
	jmp print_newline
command_echo_parameters:
	ldy #1
command_echo_next:
	lda #<parameter_prefix
	ldx #>parameter_prefix
	jsr print_text
	tya
	cmp #10
	bcc command_echo_digit
	lda #'1'
	jsr print_chr
	tya
	sec
	sbc #10
command_echo_digit:
	clc
	adc #'0'
	jsr print_chr
	lda #<parameter_separator
	ldx #>parameter_separator
	jsr print_text
	tya
	jsr command_argument
	jsr print_text
	jsr print_newline
	iny
	cpy command_argc
	bcc command_echo_next
	rts


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

.segment "RODATA"
; Add a NUL-terminated name and its handler address before the zero sentinel
; to register another command. No parser or dispatcher changes are needed.
command_table:
	.word command_echo_name, command_echo
	.word 0, 0
command_echo_name:
	.asciiz "echo"
parameter_prefix:
	.asciiz "  ["
parameter_separator:
	.asciiz "] "

prompt:
	.asciiz	"what? "
unrecognized_command:
	.asciiz "unrecognized command: "
malformed_command:
	.asciiz "malformed command (unclosed quote or too many parameters)\r\n"

.segment "VECTORS"
	.word	0			; NMI vector address
	.word	reset		; RESET vector address
	.word	0			; IRQ/BRK vector address
