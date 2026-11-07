; IMNOTWOPR host support. Uses only NMOS 6502 instructions.
; 1 MHz CPU, W65C51N at $B010, 19200 baud / 8-N-1.
; Receive IRQs buffer type-ahead; transmit is paced as in the Forth kernel.
.segment "SERIAL"
.reloc
WOPR_RX_BUFFER: .res 256
WOPR_RX_HEAD:   .res 1
WOPR_RX_TAIL:   .res 1
WOPR_RX_ERROR:  .res 1
WOPR_BREAK:     .res 1
WOPR_SKIP_LF:   .res 1
WOPR_RX_DISCARD: .res 1

.segment "PLATFORM"
.reloc
.import __LOWRAM_LOAD__, __LOWRAM_SIZE__
.assert __LOWRAM_SIZE__ = $110, lderror, "Update reset copy for changed low RAM size"
.assert BUF-4 >= $0200, error, "Input buffer overlaps CPU stack"
.assert BUF+BUFLEN <= $0400, error, "Input buffer overlaps serial queue"
.assert BUFLEN+4 <= 128, error, "Historical STOLOP uses a signed length counter"

WOPR_RESET:
    sei
    cld
    ldx #$FF
    txs
    ; The original image contains initial data and self-modifying RAM code.
    ldx #0
@copy_page:
    lda __LOWRAM_LOAD__,x
    sta $0000,x
    inx
    bne @copy_page
    ldx #$0F
@copy_tail:
    lda __LOWRAM_LOAD__+$100,x
    sta $0100,x
    dex
    bpl @copy_tail
    lda #0
    sta WOPR_RX_HEAD
    sta WOPR_RX_TAIL
    sta WOPR_RX_ERROR
    sta WOPR_BREAK
    sta WOPR_SKIP_LF
    sta WOPR_RX_DISCARD
    sta WOPR_ACIA+1         ; Programmed ACIA reset.
    lda #$1F
    sta WOPR_ACIA+3         ; 19200 baud, 8-N-1, internal receive clock.
    lda #$09
    sta WOPR_ACIA+2         ; DTR/RTS active, receive IRQ enabled, no TX IRQ.
    cli
    jmp INIT

WOPR_NMI:
    rti

WOPR_IRQ:
    pha
    txa
    pha
    lda WOPR_ACIA+1
    and #$08
    beq @done
    lda WOPR_ACIA+1
    and #$07               ; Overrun/framing/parity errors invalidate input.
    beq @read
    lda #1
    sta WOPR_RX_ERROR
    sta WOPR_RX_DISCARD
@read:
    lda WOPR_ACIA
    cmp #3
    bne @queue
    lda #1
    sta WOPR_BREAK
    bne @done
@queue:
    ldx WOPR_RX_DISCARD
    beq @store
    ; After loss, discard the rest of this line instead of executing a fragment.
    cmp #13
    beq @discard_cr
    cmp #10
    bne @done
    lda #0
    sta WOPR_RX_DISCARD
    beq @done
@discard_cr:
    lda #1
    sta WOPR_SKIP_LF
    lda #0
    sta WOPR_RX_DISCARD
    beq @done
@store:
    ldx WOPR_RX_HEAD
    sta WOPR_RX_BUFFER,x
    inx
    cpx WOPR_RX_TAIL
    beq @full
    stx WOPR_RX_HEAD
    jmp @done
@full:
    lda #1
    sta WOPR_RX_ERROR
    sta WOPR_RX_DISCARD
@done:
    pla
    tax
    pla
    rti

; Preserve A, X and Y. TDRE cannot pace writes on the W65C51N.
; 255 iterations exceed one 19200-baud frame at the profile's 1 MHz clock.
WOPR_PUTC:
    pha
    and #$7F               ; Historical error text marks its last byte with bit 7.
    sta WOPR_ACIA
    txa
    pha
    ldx #255
@delay:
    dex
    bne @delay
    pla
    tax
    pla
    rts

; BASIC calls this at each statement; input polling also checks it.
ISCNTC:
    lda WOPR_RX_ERROR
    bne @error
    lda WOPR_BREAK
    beq @done
    jsr WOPR_FLUSH
    lda #0
    sta WOPR_RX_DISCARD
    lda #3
    cmp #3                 ; STOP requires Z set and carry set for BREAK.
    jmp STOP
@error:
    jsr WOPR_FLUSH
    jsr STKINI
    lsr CNTWFL             ; Report receive failure even if Ctrl-O muted output.
    LDWDI WOPR_ERROR_TEXT
    jsr STROUT
    jmp READY
@done:
    rts

WOPR_FLUSH:
    php
    sei
    lda WOPR_RX_HEAD
    sta WOPR_RX_TAIL
    lda #0
    sta WOPR_BREAK
    sta WOPR_RX_ERROR
    sta WOPR_SKIP_LF
    plp
    rts
WOPR_ERROR_TEXT:
    .byte 13,10,"?SERIAL INPUT OVERFLOW/ERROR",13,10,0

; GET is nonblocking: A=0 if empty, otherwise the received byte. Preserve X/Y.
WOPR_TRY_GETC:
    jsr ISCNTC
    txa
    pha
    ldx WOPR_RX_TAIL
    cpx WOPR_RX_HEAD
    beq @empty
    lda WOPR_RX_BUFFER,x
    inc WOPR_RX_TAIL
    sta WOPR_KEY_TEMP
    pla
    tax
    lda WOPR_KEY_TEMP
    sec
    rts
@empty:
    pla
    tax
    lda #0
    clc
    rts

WOPR_GETC:
    jsr WOPR_TRY_GETC
    bcc WOPR_GETC
    rts

; Serial line editor. CR, LF and CR/LF terminate lines; BS and DEL erase.
; Keep case in the buffer: the historical interpreter expects uppercase keywords
; and preserves the case of string literals. Ctrl-U cancels the current line.
INLIN:
    ldx #0
WOPR_LINE_WAIT:
    jsr INCHR
    cmp #10
    bne @not_lf
    lda WOPR_SKIP_LF
    beq @finish
    lda #0
    sta WOPR_SKIP_LF
    beq WOPR_LINE_WAIT
@not_lf:
    pha
    lda #0
    sta WOPR_SKIP_LF
    pla
    cmp #13
    bne @not_cr
    lda #1
    sta WOPR_SKIP_LF
    bne @finish
@not_cr:
    cmp #8
    beq @erase
    cmp #127
    beq @erase
    cmp #21
    beq @clear
    cmp #32
    bcc WOPR_LINE_WAIT
    cmp #127
    bcs WOPR_LINE_WAIT
    cpx #BUFLEN-1
    bcs @full
    sta BUF,x
    inx
    jsr OUTDO
    jmp WOPR_LINE_WAIT
@finish:
    jmp FININL             ; Terminate BUF, return X/Y=BUF-1 and emit CR/LF.
@full:
    lda #7
    jsr WOPR_PUTC
    jmp WOPR_LINE_WAIT
@erase:
    cpx #0
    beq WOPR_LINE_WAIT
    dex
    jsr WOPR_ERASE
    jmp WOPR_LINE_WAIT
@clear:
    cpx #0
    beq WOPR_LINE_WAIT
    dex
    jsr WOPR_ERASE
    jmp @clear
WOPR_ERASE:
    lda #8
    jsr WOPR_PUTC
    lda #32
    jsr WOPR_PUTC
    lda #8
    jsr WOPR_PUTC
    lda TRMPOS
    beq @done
    dec TRMPOS
@done:
    rts

.segment "SERIAL"
WOPR_KEY_TEMP: .res 1
.segment "VECTORS"
.word WOPR_NMI, WOPR_RESET, WOPR_IRQ
