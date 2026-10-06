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
