; =============================================================================
; I2C Support 
; 
; I2C via bit banging a 65C22
; Alternative approaches to be explored.
; =============================================================================

SDA = %10000000         ; PB7
SCL = %01000000         ; PB6

; Single-controller bus, external pull-ups required. Call i2c_init first.
; Timing assumes a 1 MHz CPU; recheck bus timing before increasing PHI2.
; Byte routines preserve Y; read_byte also preserves X. Register transfers
; clobber A, X and Y. Carry reports success (0) or error (1).
; read_byte takes the ACK/NACK choice in Carry and returns status in Carry.

; Release SCL and wait for the actual pin to rise. Preserve X and Y.
; At most 256 polls (about 2 ms at 1 MHz); this is a driver timeout policy,
; not an I2C protocol limit. On timeout release both lines and return C=1.
; Success leaves A=SCL, allowing the caller to lower SCL with TSB.
i2c_scl_high:
        phy
        lda #SCL
        trb via_ddrb
        ldy #0
@wait:
        bit via_portb
        bvs @ready
        dey
        bne @wait
        lda #(SDA | SCL)
        trb via_ddrb
        ply
        sec
        rts
@ready:
        ply
        clc
        rts

; Initialize: Ensure output latches are 0, release both lines (inputs)
i2c_init:
        lda #$82            ; Disable Timer 1 PB7 output and PB input latching
        trb via_acr
        lda #(SDA | SCL)
        trb via_portb       ; Output latches = 0
        trb via_ddrb        ; DDR = 0 (both lines float high)
        clc
        rts

; START condition: SDA goes high-to-low while SCL is high
i2c_start:
        lda #SDA
        trb via_ddrb        ; Ensure SDA is released (high)
        jsr i2c_scl_high
        bcs @done
        lda #SDA
        tsb via_ddrb        ; Pull SDA low (DDR=1)
        lda #SCL
        tsb via_ddrb        ; Pull SCL low (DDR=1)
@done:
        rts

; STOP condition: SDA goes low-to-high while SCL is high
i2c_stop:
        lda #SDA
        tsb via_ddrb        ; Ensure SDA is low
        jsr i2c_scl_high
        bcs @done
        lda #SDA
        trb via_ddrb        ; Release SDA (goes high)
@done:
        rts

; Write 1 byte in A; returns C=0 for ACK, C=1 for NACK or timeout.
; Entry: SCL low. X clobbered, Y preserved.
i2c_write_byte:
        ldx #8              ; 8 bits to send
@loop:
        asl                 ; Shift MSB into Carry
        pha                 ; Save remaining bits
        bcs @send_one
        lda #SDA
        tsb via_ddrb        ; Bit is 0 -> Pull SDA low
        bra @clock
@send_one:
        lda #SDA
        trb via_ddrb        ; Bit is 1 -> Release SDA high
@clock:
        jsr i2c_scl_high
        bcs @data_timeout
        tsb via_ddrb        ; Pull SCL low
        pla                 ; Restore remaining bits
        dex
        bne @loop

        ; Read 9th bit (ACK/NACK from target device)
        lda #SDA
        trb via_ddrb        ; Release SDA so target can pull it low
        jsr i2c_scl_high
        bcs @nack
        bit via_portb       ; Sample SDA into N flag (Bit 7)
        php                 ; Save N flag status
        lda #SCL
        tsb via_ddrb        ; Pull SCL low
        plp                 ; Restore flags
        bmi @nack           ; If N=1 (SDA high), target did not ACK
        clc                 ; Carry = 0 (ACK)
        rts
@nack:
        sec                 ; Carry = 1 (NACK)
        rts
@data_timeout:
        pla                 ; Discard remaining bits before returning
        sec
        rts

; ---------------------------------------------------------------------------
; Read 1 byte from bus into A
; Entry: Carry = 0 to send ACK (more bytes follow)
;        Carry = 1 to send NACK (last byte)
; Entry: SCL low.
; Exit: C=0: A = received byte; C=1: timeout, A undefined. X, Y preserved.
; ---------------------------------------------------------------------------
i2c_read_byte:
        phx                     ; Preserve caller's X register on stack
        phy                     ; Preserve caller's buffer offset
        php                     ; Save caller's Carry (ACK/NACK choice) on top
        lda #SDA
        trb via_ddrb                ; Release SDA so target can drive data
        ldx #0                  ; X will hold the incoming byte
        ldy #8                  ; 8 bits to read
@bit_loop:
        jsr i2c_scl_high
        bcs @data_timeout
        bit via_portb               ; Sample SDA (Bit 7 -> N flag)
        clc
        bpl @zero               ; SDA=0 -> Carry=0
        sec                     ; SDA=1 -> Carry=1
@zero:
        txa                     ; Move partial byte from X to A
        rol a                   ; Shift Carry into bit 0
        tax                     ; Save updated byte back in X
        lda #SCL
        tsb via_ddrb                ; Pull SCL low
        dey
        bne @bit_loop

        ; Send 9th bit (Controller ACK or NACK)
        plp                     ; Restore ACK/NACK from Carry
        bcs @send_nack
        lda #SDA
        tsb via_ddrb                ; Carry=0 -> Pull SDA low (ACK)
        bra @clock_ack
@send_nack:
        lda #SDA
        trb via_ddrb                ; Carry=1 -> Release SDA high (NACK)
@clock_ack:
        jsr i2c_scl_high
        bcs @ack_timeout
        tsb via_ddrb                ; Pull SCL low
        lda #SDA
        trb via_ddrb                ; Always release SDA after ACK
        txa                     ; Move final assembled byte into A
        ply
        plx                     ; Restore caller's X register
        clc
        rts
@data_timeout:
        plp                     ; Discard saved ACK/NACK choice
@ack_timeout:
        ply
        plx
        sec
        rts

; ---------------------------------------------------------------------------
; Write i2c_len bytes from (i2c_ptr) to i2c_addr starting at i2c_reg
; Length must be 1..255; zero is rejected without touching the bus.
; Exit: C=0 on success, C=1 for NACK, timeout or zero length. A, X, Y clobbered.
; ---------------------------------------------------------------------------
i2c_write_reg:
        lda i2c_len
        bne @begin
        sec
        rts
@begin:
        jsr i2c_start
        bcs @abort
        lda i2c_addr
        asl                     ; Shift 7-bit address left; bit 0 = 0 (Write)
        jsr i2c_write_byte
        bcs @abort              ; Abort if target did not ACK address

        lda i2c_reg             ; Send target register address
        jsr i2c_write_byte
        bcs @abort

        ldy #0
@write_loop:
        lda (i2c_ptr),y
        jsr i2c_write_byte
        bcs @abort
        iny
        cpy i2c_len
        bne @write_loop

        jmp i2c_stop             ; Propagate a STOP timeout to the caller
@abort:
        jsr i2c_stop
        sec                     ; Preserve failure even if STOP succeeds
        rts

; ---------------------------------------------------------------------------
; Read i2c_len bytes into (i2c_ptr) from i2c_addr starting at i2c_reg
; Uses a Repeated START between setting the register and reading data
; Length must be 1..255; zero is rejected without touching the bus.
; Exit: C=0 on success, C=1 for NACK, timeout or zero length. A, X, Y clobbered.
; On failure, bytes already transferred remain in the buffer.
; ---------------------------------------------------------------------------
i2c_read_reg:
        lda i2c_len
        bne @begin
        sec
        rts
@begin:
        jsr i2c_start
        bcs @abort
        lda i2c_addr
        asl                     ; 7-bit address + Write (0)
        jsr i2c_write_byte
        bcs @abort

        lda i2c_reg             ; Set internal register pointer on target
        jsr i2c_write_byte
        bcs @abort

        jsr i2c_start           ; Repeated START (no STOP in between)
        bcs @abort
        lda i2c_addr
        asl
        ora #$01                ; 7-bit address + Read (1)
        jsr i2c_write_byte
        bcs @abort

        ldy #0
@read_loop:
        iny
        cpy i2c_len             ; Is this the final byte?
        beq @last_byte
        dey
        clc                     ; Carry = 0 -> Send ACK for more bytes
        jsr i2c_read_byte
        bcs @abort
        sta (i2c_ptr),y
        iny
        bra @read_loop

@last_byte:
        dey
        sec                     ; Carry = 1 -> Send NACK on final byte
        jsr i2c_read_byte
        bcs @abort
        sta (i2c_ptr),y

        jmp i2c_stop             ; Propagate a STOP timeout to the caller
@abort:
        jsr i2c_stop
        sec                     ; Preserve failure even if STOP succeeds
        rts

; ---------------------------------------------------------------------------
; Scan 7-bit I2C addresses $08 through $77
; Entry: A/X = callback address (low/high); $0000 disables reporting.
; Calls the callback after STOP with the responding 7-bit address in A.
; Callback may clobber A/X/Y and flags, but must balance the stack and must
; not recursively scan the bus. C=0 when finished, C=1 if START/STOP
; times out. A and X clobbered; Y preserved. Failed probes are skipped.
; ---------------------------------------------------------------------------
i2c_scan_bus:
        sta i2c_scan_callback
        stx i2c_scan_callback+1
        jsr i2c_init            ; Ensure bus is idle and lines are released
        lda #$08                ; First valid non-reserved 7-bit address
        sta i2c_scan_addr

@next_addr:
        jsr i2c_start           ; Issue START condition
        bcs @error
        lda i2c_scan_addr
        asl                     ; Shift left; bit 0 = 0 (Write probe)
        jsr i2c_write_byte      ; Returns Carry = 0 if ACK, Carry = 1 if NACK
        php                     ; Save ACK/NACK result (Carry flag)
        jsr i2c_stop            ; Always release bus cleanly with STOP
        bcs @stop_timeout
        plp                     ; Restore Carry flag
        bcs @no_device          ; If Carry = 1 (NACK), nothing at this address

        lda i2c_scan_callback
        ora i2c_scan_callback+1
        beq @no_device
        phy                     ; Preserve scanner's Y across user callback
        lda i2c_scan_addr       ; Load 7-bit address that responded
        jsr i2c_scan_report
        ply

@no_device:
        inc i2c_scan_addr       ; Advance to next 7-bit address
        lda i2c_scan_addr
        cmp #$78                ; Stop before reserved $78..$7F range
        bne @next_addr
        clc
        rts
@stop_timeout:
        plp                     ; Balance saved probe status
@error:
        sec
        rts

; Indirect JSR: callback's RTS returns to the scanner's JSR above.
i2c_scan_report:
        jmp (i2c_scan_callback)


; ; I2C Example: reading time from a DS3231 RTC
; ; Read the 7 timekeeping registers ($00 through $06) from a DS3231 
; ; real-time clock (70bit address $68) into a RAM buffer at $0300
; read_rtc_time:
;         lda #$68                ; DS3231 7-bit I2C address
;         sta i2c_addr
;         lda #$00                ; Start at Seconds register ($00)
;         sta i2c_reg
;         lda #<rtc_buf           ; Destination buffer low byte ($00)
;         sta i2c_ptr
;         lda #>rtc_buf           ; Destination buffer high byte ($03)
;         sta i2c_ptr+1
;         lda #7                  ; Read 7 bytes (Sec, Min, Hr, Day, Date, Mon, Yr)
;         sta i2c_len

;         jsr i2c_read_reg
;         bcs @rtc_error          ; Handle missing device / NACK
;         rts
; @rtc_error:
;         ; Error handling routine here
;         rts

; rtc_buf = $0300
