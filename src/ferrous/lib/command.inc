; Command interface: command_argc counts the command plus its parameters.
; command_argv holds byte offsets into command_buffer, one per NUL-terminated
; value. Index 0 is the command name; indexes 1..command_argc-1 are parameters.
; command_argument takes an index in A and returns its address in A/X.
; Values remain available until the next parse. All routines are non-reentrant.
COMMAND_MAX_ARGS = 16		; Command name plus at most 15 parameters.

.segment "ZEROPAGE"
command_table_ptr:	.res 2
command_handler:	.res 2

.segment "BSS"
command_buffer:	.res 256
command_argv:	.res COMMAND_MAX_ARGS
command_argc:	.res 1
command_quote:	.res 1

.segment "PROGRAM_CODE"
; Parse input_buffer without modifying the original line (used by diagnostics).
; Spaces separate values; double quotes group spaces and are removed. Adjacent
; quoted/unquoted pieces form one value, and "" is an empty value. Backslashes
; and single quotes are literal. Returns C clear on success, set on error;
; an error clears argc so partially parsed commands cannot be executed.
; Clobbers A/X/Y and flags. Input must be NUL-terminated within 256 bytes.
command_parse:
	stz command_argc
	ldx #0			; Source offset.
	ldy #0			; Destination offset (never ahead of source).
command_parse_space:
	lda input_buffer,x
	beq command_parse_done
	cmp #' '
	bne command_parse_start
	inx
	bra command_parse_space
command_parse_start:
	lda command_argc
	cmp #COMMAND_MAX_ARGS
	beq command_parse_error
	phx
	tax
	tya
	sta command_argv,x
	plx
	inc command_argc
	stz command_quote
command_parse_character:
	lda input_buffer,x
	beq command_parse_end
	cmp #'"'
	beq command_parse_quote
	cmp #' '
	bne command_parse_copy
	lda command_quote
	beq command_parse_separator
	lda #' '
command_parse_copy:
	sta command_buffer,y
	iny
	inx
	bra command_parse_character
command_parse_quote:
	lda command_quote
	eor #1
	sta command_quote
	inx
	bra command_parse_character
command_parse_separator:
	lda #0
	sta command_buffer,y
	iny
	inx
	bra command_parse_space
command_parse_end:
	lda command_quote
	bne command_parse_error
command_parse_done:
	lda #0
	sta command_buffer,y
	clc
	rts
command_parse_error:
	stz command_argc
	sec
	rts

; A = valid argument index (0 <= A < command_argc).
; Returns A = address low, X = address high; preserves Y, clobbers flags.
command_argument:
	tax
	lda command_argv,x
	clc
	adc #<command_buffer
	ldx #>command_buffer
	bcc command_argument_done
	inx
command_argument_done:
	rts

; Find an exact, case-sensitive name in the table and call its handler.
; Handlers read argc/argv via command_argument and return with RTS. They may
; clobber A/X/Y and flags. Returns C clear if executed, set if unknown/empty.
command_execute:
	lda command_argc
	beq command_execute_unknown
	lda #<command_table
	sta command_table_ptr
	lda #>command_table
	sta command_table_ptr+1
command_execute_find:
	ldy #0
	lda (command_table_ptr),y
	sta compare_text_right
	iny
	lda (command_table_ptr),y
	sta compare_text_right+1
	ora compare_text_right
	beq command_execute_unknown
	lda #0
	jsr command_argument
	sta compare_text_left
	stx compare_text_left+1
	jsr compare_text
	beq command_execute_found
	clc
	lda command_table_ptr
	adc #4
	sta command_table_ptr
	bcc command_execute_find
	inc command_table_ptr+1
	bra command_execute_find
command_execute_found:
	ldy #2
	lda (command_table_ptr),y
	sta command_handler
	iny
	lda (command_table_ptr),y
	sta command_handler+1
	jsr command_execute_call
	clc
	rts
command_execute_call:
	jmp (command_handler)	; Handler's RTS returns to the JSR above.
command_execute_unknown:
	sec
	rts

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

.segment "PROGRAM_CODE"
