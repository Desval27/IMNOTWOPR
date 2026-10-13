; ============================================================================
; Monitor
; ============================================================================

.import acia_init
.import read_text
.import input_buffer
.import print_text
.import print_newline
.import print_chr
.import compare_text
.importzp compare_text_left, compare_text_right

.segment "ZEROPAGE"
mem_ptr:        .res 2
hex_ptr:        .res 2

.segment "BSS"
mem_end:        .res 2
mem_count:      .res 1
mem_done:       .res 1
mem_row:        .res 16
hex_value:      .res 2

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

; ----------------------------------------------------------------------------
; FORMAT: mem low_address high_address (inclusive, 1..4 hex digits each).
command_mem:
	lda command_argc
	cmp #3
	beq do_command_mem
	jmp do_help_mem_usage
do_command_mem:
	lda #1
	jsr command_argument
	jsr parse_hex_address
	bcs command_mem_invalid
	sta mem_ptr
	stx mem_ptr+1
	lda #2
	jsr command_argument
	jsr parse_hex_address
	bcs command_mem_invalid
	sta mem_end
	stx mem_end+1
	; Reject reversed ranges before reading any memory.
	lda mem_ptr+1
	cmp mem_end+1
	bcc command_mem_start
	bne command_mem_invalid
	lda mem_ptr
	cmp mem_end
	bcc command_mem_start
	beq command_mem_start
command_mem_invalid:
	jmp do_help_mem_usage
command_mem_start:
	stz mem_done
command_mem_row:
	lda mem_ptr+1
	jsr print_hex_byte
	lda mem_ptr
	jsr print_hex_byte
	lda #':'
	jsr print_chr
	stz mem_count
command_mem_byte:
	lda #' '
	jsr print_chr
	; Save each byte once, so the ASCII column does not reread I/O.
	lda (mem_ptr)
	ldx mem_count
	sta mem_row,x
	jsr print_hex_byte
	inc mem_count
	lda mem_ptr
	cmp mem_end
	bne command_mem_next
	lda mem_ptr+1
	cmp mem_end+1
	bne command_mem_next
	inc mem_done		; Stop before incrementing $FFFF and wrapping.
	bra command_mem_padding
command_mem_next:
	inc mem_ptr
	bne command_mem_check_row
	inc mem_ptr+1
command_mem_check_row:
	lda mem_count
	cmp #16
	bne command_mem_byte
command_mem_padding:
	ldx mem_count
command_mem_pad:
	cpx #16
	beq command_mem_ascii
	lda #' '
	jsr print_chr
	jsr print_chr
	jsr print_chr
	inx
	bra command_mem_pad
command_mem_ascii:
	lda #' '
	jsr print_chr
	jsr print_chr
	lda #'|'
	jsr print_chr
	ldx #0
command_mem_ascii_byte:
	lda mem_row,x
	cmp #$20
	bcc command_mem_dot
	cmp #$7f
	bcc command_mem_ascii_print
command_mem_dot:
	lda #'.'
command_mem_ascii_print:
	jsr print_chr
	inx
	cpx mem_count
	bne command_mem_ascii_byte
	lda #'|'
	jsr print_chr
	jsr print_newline
	lda mem_done
	bne command_mem_finished
	jmp command_mem_row
command_mem_finished:
	rts

; A/X = NUL-terminated string address. Accept exactly 1..4 hex digits.
; Returns A/X = 16-bit value and C clear, or C set on invalid input.
; Clobbers Y and flags; no prefixes, signs, whitespace or trailing junk.
parse_hex_address:
	sta hex_ptr
	stx hex_ptr+1
	stz hex_value
	stz hex_value+1
	ldy #0
parse_hex_digit:
	lda (hex_ptr),y
	beq parse_hex_end
	cpy #4
	bcs parse_hex_invalid
	cmp #'0'
	bcc parse_hex_invalid
	cmp #'9'+1
	bcc parse_hex_decimal
	and #$df		; Fold a..f to A..F.
	cmp #'A'
	bcc parse_hex_invalid
	cmp #'F'+1
	bcs parse_hex_invalid
	sec
	sbc #'A'-10
	bra parse_hex_accumulate
parse_hex_decimal:
	sec
	sbc #'0'
parse_hex_accumulate:
	ldx #4
parse_hex_shift:
	asl hex_value
	rol hex_value+1
	dex
	bne parse_hex_shift
	ora hex_value
	sta hex_value
	iny
	bra parse_hex_digit
parse_hex_end:
	cpy #0
	beq parse_hex_invalid
	lda hex_value
	ldx hex_value+1
	clc
	rts
parse_hex_invalid:
	sec
	rts

; Print A as two uppercase hex digits; preserves X/Y, clobbers A/flags.
print_hex_byte:
	pha
	lsr
	lsr
	lsr
	lsr
	jsr print_hex_nibble
	pla
	and #$0f
print_hex_nibble:
	cmp #10
	bcc print_hex_decimal
	clc
	adc #'A'-10
	jmp print_chr
print_hex_decimal:
	clc
	adc #'0'
	jmp print_chr

; ----------------------------------------------------------------------------
command_help:
	lda #<no
	ldx #>no
	jsr print_text
	jsr do_help_mem
	rts

do_help_mem_usage:
	lda #<usage
	ldx #>usage
	jsr print_text
do_help_mem:	
	lda #<help_mem
	ldx #>help_mem
	jsr print_text
	rts 

; ============================================================================
.segment "RODATA"
; Add a NUL-terminated name and its handler address before the zero sentinel
; to register another command. No parser or dispatcher changes are needed.
command_table:
	.word command_help_name, command_help
	.word command_mem_name, command_mem
	.word 0, 0
command_help_name:
	.asciiz "help"
command_mem_name:
	.asciiz "mem"	
help_mem: 
	.asciiz "mem low_address high_address (1-4 hex digits, inclusive)\r\n"
	

prompt:
	.asciiz	": "
unrecognized_command:
	.asciiz "?"
malformed_command:
	.asciiz "malformed"
usage:
	.asciiz "usage: "
no:
	.asciiz "no\r\n"

.segment "VECTORS"
	.word	0			; NMI vector address
	.word	reset		; RESET vector address
	.word	0			; IRQ/BRK vector address
