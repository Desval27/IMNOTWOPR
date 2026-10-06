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

; Print CR/LF, preserving X/Y.
print_newline:
	lda	#$0D
	jsr	print_chr
	lda	#$0A
	jmp	print_chr

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
