; Configuration
USE_EXTENDED_TEXT = 1	; Set to 1 to allow for text strings longer than 255 bytes.  

PRINT_CHR_DELAY = $FF	; Set to a value that will give the ACIA time to send a character before the next one is sent.  This is a crude way to do it, but it works for now.

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

; ============================================================================
; compare_text: Case-sensitive equality of two NUL-terminated byte strings.
; Inputs: compare_text_left and compare_text_right hold little-endian addresses.
; Returns A = 0, Z = 1 if equal; A = 1, Z = 0 otherwise (BEQ means equal).
; Preserves X; clobbers Y and flags. Advances both pointers for each 256 bytes
; compared, so reload them before reuse. Supports strings longer than 255 bytes.
; Not reentrant. Both strings must be NUL-terminated.
; ============================================================================
compare_text:
	ldy	#0
compare_text_loop:
	lda	(compare_text_left),y
	cmp	(compare_text_right),y
	bne	compare_text_different
	cmp	#0
	beq	compare_text_equal
	iny
	bne	compare_text_loop
	inc	compare_text_left+1
	inc	compare_text_right+1
	bra	compare_text_loop
compare_text_equal:
	lda	#0
	rts
compare_text_different:
	lda	#1
	rts

; ============================================================================
; read_text: Read and echo a line into a 256-byte buffer at A (low), X (high).
; Returns Y = length (0..255), with a trailing NUL stored in the buffer.
; Preserves X; clobbers A, Y, flags and read_text_ptr (not reentrant).
; CR, LF or CR/LF finishes the line and echoes one CR/LF. Backspace/Delete
; erases a character. Other non-printable ASCII is ignored. At capacity,
; additional printable characters ring the bell and are not stored/echoed.
; skip_lf must be initialized to zero once before the first call.
; This polls the ACIA; input must be paced while echo/reverse output is sent.
; ============================================================================
read_text:
	sta	read_text_ptr
	stx	read_text_ptr+1
	ldy	#0
read_text_loop:
	jsr	read_chr
	cmp	#$0A
	beq	read_text_lf
	stz	skip_lf
	cmp	#$0D
	beq	read_text_cr
	cmp	#$08
	beq	read_text_erase
	cmp	#$7F
	beq	read_text_erase
	cmp	#$20
	bcc	read_text_loop
	cmp	#$7F
	bcs	read_text_loop
	cpy	#$FF
	beq	read_text_full
	sta	(read_text_ptr),y
	iny
	jsr	print_chr
	bra	read_text_loop
read_text_full:
	lda	#$07		; Bell: buffer is full.
	jsr	print_chr
	bra	read_text_loop
read_text_erase:
	cpy	#0
	beq	read_text_loop
	dey
	lda	#$08
	jsr	print_chr
	lda	#' '
	jsr	print_chr
	lda	#$08
	jsr	print_chr
	bra	read_text_loop
read_text_lf:
	lda	skip_lf
	beq	read_text_done
	stz	skip_lf
	bra	read_text_loop
read_text_cr:
	lda	#1
	sta	skip_lf
read_text_done:
	lda	#0
	sta	(read_text_ptr),y
	jsr	print_newline
	rts

; Wait for an ACIA receive byte. Returns A; preserves X/Y.
read_chr:
	lda	acia_status
	and	#$08		; Receive data register full.
	beq	read_chr
	lda	acia_data
	rts

; Print CR/LF, preserving X/Y.
print_newline:
	lda	#$0D
	jsr	print_chr
	lda	#$0A
	jmp	print_chr

; ============================================================================
; print_text:  Print a NUL-terminated string at address A (low byte), X (high byte).
; example:
;	lda	#<greeting
;	ldx	#>greeting
;	jsr	print_text
; ============================================================================
.if USE_EXTENDED_TEXT = 1
; Extended text support: Can handle strings longer than 255 bytes, but not reentrant.
; print a NUL-terminated string at address A (low byte), X (high byte).
; Preserves X and Y; clobbers A, flags and print_text_ptr (not reentrant).
print_text:
	sta	print_text_ptr
	stx	print_text_ptr+1
	phy				; Save registers
	ldy	#0			; Start at the beginning of the string.
print_text_loop:
	lda	(print_text_ptr),y	; Get the next character.
	beq	print_text_done	; If it's zero, we're done.
	jsr	print_chr	; Otherwise, print it.
	iny				; Move to the next character.
	bne	print_text_loop
	inc	print_text_ptr+1	; Continue past 256 bytes when Y wraps.
	bra	print_text_loop
print_text_done:
	ply				; Restore registers
	rts				; Return

.else

; Smaller alternative for NUL-terminated strings of 0..255 text bytes.
; Same A/X address parameter and register contract as print_text.
; The string may cross a page boundary; no pointer update is needed.
print_text:
	sta	print_text_ptr
	stx	print_text_ptr+1
	phy
	ldy	#0
print_text_loop:
	lda	(print_text_ptr),y
	beq	print_text_done
	jsr	print_chr
	iny
	bne	print_text_loop
print_text_done:
	ply
	rts
.endif

; ============================================================================
; Print a single character in A to the ACIA.  This is a blocking call that 
; waits for the ACIA to be ready.	
; ============================================================================
print_chr:
	sta	acia_data	; Output character.  This is the easy bit.

	; Now we need to wait a bit before we can send the next character.
	phx
	ldx	#PRINT_CHR_DELAY
print_chr_loop:
	dex
	bne print_chr_loop
	plx
	rts				; Return

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
