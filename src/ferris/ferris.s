	.org	$C000

ACIA_DATA	= $8010
ACIA_STATUS	= $8011
ACIA_CMD	= $8012
ACIA_CTRL	= $8013

RESET:
	sei
	cld
	ldx	#$ff
	txs

	; ACIA Init
	lda	#$1F		; 8-N-1, 19200 baud
	sta	ACIA_CTRL
	lda	#$0B		; No parity, no echo, no interrupts.
	sta	ACIA_CMD

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
	sta	ACIA_DATA	; Output character.
	phx
	ldx	#$66
print_delay:
	dex
	bne print_delay
	plx
	rts				; Return

message:
	.asciiz	"Hello, World!"

	.org	$FFFA
	.word	$0F00		; NMI vector
	.word	$RESET		; RESET vector
	.word 	$0000		; IRQ vector
