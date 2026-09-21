.segment "VIA"
via_portb:		.res	1
via_porta:		.res	1
via_ddrb:		.res	1
via_ddra:		.res	1

.segment "ACIA"
acia_data:		.res	1
acia_status:	.res	1
acia_cmd:		.res	1
acia_ctrl:		.res	1

.segment "CODE"
reset:
	sei
	cld
	ldx	#$ff
	txs

	; ACIA Init
	lda	#$1F		; 8-N-1, 19200 baud
	sta	acia_ctrl
	lda	#$0B		; No parity, no echo, no interrupts.
	sta	acia_cmd

	ldx #$00
print:
	lda	message, x
	beq loop
	jsr	print_chr
	inx
	jmp	print
	jsr crlf

loop:
	jmp	loop

crlf:
	lda #$0A
	jsr print_chr
	lda #$0D
	jsr print_chr
	rts

print_chr:
	sta	acia_data	; Output character.
	phx
	ldx	#$66
print_delay:
	dex
	bne print_delay
	plx
	rts				; Return

message:
	.asciiz	"Hello, World!"

.segment "VECTORS"
	.word	0			; NMI vector address
	.word	reset		; RESET vector address
	.word	0			; IRQ/BRK vector address
