; IMNOTWOPR host support for the original indirect-threaded Forth core.
; All interrupt state is separate from the Forth registers in zero page.
.segment "BSS"
rx_buffer:          .res 256
rx_head:            .res 1
rx_tail:            .res 1
rx_overflow:        .res 1
break_requested:    .res 1
input_skip_lf:      .res 1
expect_limit:       .res 1
expect_length:      .res 1
expect_overflow:    .res 1
memory_limit:       .res 2
definition_active:  .res 1
definition_dp:      .res 2
definition_head:    .res 2
definition_current: .res 2
error_number:       .res 1
error_length:       .res 1

.segment "PROGRAM_CODE"

; Unsupported dictionary entries are native CFAs, not colon definitions.
NO_C64:
    lda #26
    jmp shell_error
C64_ERROR:
    .word NO_C64

shell_nmi:
    rti

; The ACIA generates receive interrupts; transmit uses the board's existing
; paced print_chr. A 255-byte queue permits type-ahead while output is busy.
shell_irq:
    pha
    phx
    lda acia_status
    and #$08
    beq @done
    lda acia_data
    cmp #3
    bne @queue
    lda #1
    sta break_requested
    bra @done
@queue:
    ldx rx_head
    sta rx_buffer,x
    inx
    cpx rx_tail
    beq @full
    stx rx_head
    bra @done
@full:
    lda #1
    sta rx_overflow
@done:
    plx
    pla
    rti

serial_try_key:
    lda break_requested
    beq :+
    jmp shell_break
:   lda rx_overflow
    beq :+
    lda #28
    jmp shell_error
:   phx
    ldx rx_tail
    cpx rx_head
    beq @empty
    lda rx_buffer,x
    inc rx_tail
    plx
    sec
    rts
@empty:
    plx
    clc
    rts

serial_key:
serial_wait_key:
    jsr serial_try_key
    bcc serial_wait_key
    rts

shell_cold:
    sei
    cld
    ldx #$FF
    txs
    stz rx_head
    stz rx_tail
    stz rx_overflow
    stz break_requested
    stz input_skip_lf
    stz definition_active
    jsr acia_init
    lda #$09                 ; Receiver IRQ enabled, transmitter enabled.
    sta acia_cmd
    lda #0
    ldx #0
@clear_user:
    sta USRINI,x
    inx
    bne @clear_user
    ldx #21
@copy_user:
    lda ORIG+12,x
    sta USRINI,x
    dex
    bpl @copy_user
    jsr reset_dictionary
    lda #<DICT_END
    sta memory_limit
    lda #>DICT_END
    sta memory_limit+1
    cli
    ldy #0
@banner:
    lda shell_banner,y
    beq @ready
    jsr print_chr
    iny
    bra @banner
@ready:
    jmp shell_abort
shell_banner:
    .byte "WHOPPING FORTH",13,10,"16-bit serial shell; Ctrl-C aborts.",13,10,0

shell_empty:
    stz definition_active
    jsr reset_dictionary
    jmp shell_abort

reset_dictionary:
    ldx #VOCABULARY_LATEST_TABLE-FORTH_NFA-1
@copy:
    lda FORTH_NFA,x
    sta RAMVOC,x
    dex
    bpl @copy
    lda #<DICT_START
    sta USRINI+$10
    sta USRINI+$12
    lda #>DICT_START
    sta USRINI+$11
    sta USRINI+$13
    lda #<(RAMVOC+EDITOR_LATEST-FORTH_NFA+2)
    sta USRINI+$14
    lda #>(RAMVOC+EDITOR_LATEST-FORTH_NFA+2)
    sta USRINI+$15
    rts

; ABORT preserves completed definitions. COLD resets dictionary allocation.
shell_abort:
    lda #10
    sta USRINI+$26
    stz USRINI+$27
    jsr rollback_definition
    jmp shell_restart

shell_break:
    sei
    lda rx_head
    sta rx_tail
    stz break_requested
    cli
    lda #30
    jmp shell_error

shell_error:
    sta error_number
    cld
    ldx #$FF
    txs
    lda rx_overflow
    beq :+
    sei
    lda rx_head
    sta rx_tail
    stz rx_overflow
    cli
:   jsr print_newline
    lda #'?'
    jsr print_chr
    lda #' '
    jsr print_chr
    lda error_number
    cmp #(ERROR_TABLE_END-ERROR_TABLE)/2
    bcc :+
    lda #4                   ; UNKNOWN ERROR
:   asl a
    tay
    lda ERROR_TABLE,y
    sta NXTMP
    lda ERROR_TABLE+1,y
    sta NXTMP+1
    ldy #0
    lda (NXTMP),y
    sta error_length
@message:
    iny
    lda (NXTMP),y
    jsr print_chr
    cpy error_length
    bne @message
    jsr print_newline
    jsr rollback_definition
    jmp shell_restart

rollback_definition:
    lda definition_active
    beq @done
    lda definition_dp
    sta USRINI+$12
    lda definition_dp+1
    sta USRINI+$13
    lda definition_current
    sta NXTMP
    lda definition_current+1
    sta NXTMP+1
    ldy #0
    lda definition_head
    sta (NXTMP),y
    iny
    lda definition_head+1
    sta (NXTMP),y
    stz definition_active
@done:
    rts

shell_restart:
    cld
    ldx #$FF
    txs
    lda #<USRINI
    sta UP
    lda #>USRINI
    sta UP+1
    lda #<(RAMVOC+FORTH_LATEST-FORTH_NFA)
    sta USRINI+$20
    sta USRINI+$22
    lda #>(RAMVOC+FORTH_LATEST-FORTH_NFA)
    sta USRINI+$21
    sta USRINI+$23
    stz USRINI+$24            ; STATE: interpreting
    stz USRINI+$25
    stz USRINI+$16            ; BLK: terminal input
    stz USRINI+$17
    stz USRINI+$18            ; IN
    stz USRINI+$19
    stz USRINI+$1A            ; OUT
    stz USRINI+$1B
    ldx #29
@vectors:
    lda VWORDS+2,x
    sta USRINI+$32,x
    dex
    bpl @vectors
    ldx #TOS
    lda #<shell_thread
    sta IP
    lda #>shell_thread
    sta IP+1
    cli
    jmp NEXT
shell_thread:
    .word QUIT

BEGIN_DEFINITION:
    .word *+2
    lda USRINI+$12
    sta definition_dp
    lda USRINI+$13
    sta definition_dp+1
    lda USRINI+$22
    sta definition_current
    sta NXTMP
    lda USRINI+$23
    sta definition_current+1
    sta NXTMP+1
    ldy #0
    lda (NXTMP),y
    sta definition_head
    iny
    lda (NXTMP),y
    sta definition_head+1
    lda #1
    sta definition_active
    jmp NEXT
END_DEFINITION:
    .word *+2
    stz definition_active
    jmp NEXT

UPPER_TOKEN:
    .word *+2
    lda USRINI+$12
    sta NXTMP
    lda USRINI+$13
    sta NXTMP+1
    ldy #0
    lda (NXTMP),y
    sta N
    beq @done
@next:
    iny
    lda (NXTMP),y
    cmp #'a'
    bcc @skip
    cmp #'z'+1
    bcs @skip
    and #$DF
    sta (NXTMP),y
@skip:
    cpy N
    bne @next
@done:
    jmp NEXT

; EXPECT ( address maximum -- ): ASCII line editing, CR/LF/CRLF, BS/DEL,
; with two NUL terminators as required by the original WORD/ENCLOSE parser.
expect_serial:
    REQUIRE_CELLS 2
    lda 2,x
    sta NXTMP
    lda 3,x
    sta NXTMP+1
    lda 0,x
    sta expect_limit
    lda 1,x
    beq :+
    lda #$FF
    sta expect_limit
:   stz expect_length
    stz expect_overflow
@read:
    jsr serial_key
    cmp #10
    beq @lf
    stz input_skip_lf
    cmp #13
    beq @cr
    cmp #8
    beq @erase
    cmp #127
    beq @erase
    cmp #32
    bcc @read
    cmp #127
    bcs @read
    ldy expect_length
    cpy expect_limit
    beq @full
    sta (NXTMP),y
    inc expect_length
    jsr print_chr
    bra @read
@full:
    lda #1
    sta expect_overflow
    lda #7
    jsr print_chr
    bra @read
@erase:
    lda expect_length
    beq @read
    dec expect_length
    lda #8
    jsr print_chr
    lda #' '
    jsr print_chr
    lda #8
    jsr print_chr
    bra @read
@lf:
    lda input_skip_lf
    beq @done
    stz input_skip_lf
    bra @read
@cr:
    lda #1
    sta input_skip_lf
@done:
    lda expect_overflow
    beq :+
    lda #32
    jmp shell_error
:
    ldy expect_length
    lda #0
    sta (NXTMP),y
    iny
    bne :+
    inc NXTMP+1
:   sta (NXTMP),y
    jsr print_newline
    jmp POPTWO

; Dictionary storage leaves 256 bytes for WORD, PAD and numeric formatting.
; ALLOT accepts a signed delta, but cannot retreat below the RAM dictionary.
allot_checked:
    REQUIRE_CELLS 1
    clc
    lda USRINI+$12
    adc 0,x
    sta N
    lda USRINI+$13
    adc 1,x
    sta N+1
    lda 1,x
    bmi @negative
    bcs dictionary_full
    bra @bounds
@negative:
    bcc dictionary_full
@bounds:
    jsr dictionary_bounds
    lda N
    sta USRINI+$12
    lda N+1
    sta USRINI+$13
    jmp POP

dictionary_bounds:
    lda N
    cmp #<DICT_START
    lda N+1
    sbc #>DICT_START
    bcc dictionary_full
    lda #<(DICT_END-DICT_WORKSPACE)
    cmp N
    lda #>(DICT_END-DICT_WORKSPACE)
    sbc N+1
    bcc dictionary_full
    rts
dictionary_full:
    lda #2
    jmp shell_error

dictionary_room:
    clc
    adc USRINI+$12
    sta N
    lda USRINI+$13
    adc #0
    sta N+1
    bcs dictionary_full
    jsr dictionary_bounds
    lda USRINI+$12
    sta NXTMP
    lda USRINI+$13
    sta NXTMP+1
    lda N
    sta USRINI+$12
    lda N+1
    sta USRINI+$13
    ldy #0
    rts

comma_checked:
    REQUIRE_CELLS 1
    lda #2
    jsr dictionary_room
    lda 0,x
    sta (NXTMP),y
    iny
    lda 1,x
    sta (NXTMP),y
    jmp POP

ccomma_checked:
    REQUIRE_CELLS 1
    lda #1
    jsr dictionary_room
    lda 0,x
    sta (NXTMP),y
    jmp POP
