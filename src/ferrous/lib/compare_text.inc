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

