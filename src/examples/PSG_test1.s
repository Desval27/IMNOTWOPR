; ==============================================================================
; AY-3-8910 DIRECT-MAPPED MEMORY INTERFACE TEST (65C02)
; Target Assembler: ca65
; ==============================================================================

.segment "ZEROPAGE"

.segment "BSS"

.segment "PSG"
psg_data:			.res	1
psg_blank1:         .res    1
psg_addr:           .res    1
psg_blank2:         .res    1

; --- Hardware Mapping Definitions ---
; PSG_DATA = $4000        ; Base + 0: Write register data
; PSG_ADDR = $4002        ; Base + 2: Latch register address / Read register data

; --- AY-3-8910 Register Definitions ---
R0_TONE_A_LO   = $00     ; Channel A Tone Period (Fine)
R1_TONE_A_HI   = $01     ; Channel A Tone Period (Coarse)
R7_ENABLE      = $07     ; Mixer / I/O Enable Control Register
R8_AMP_A       = $08     ; Channel A Amplitude (Volume)

.segment "CODE"

.proc main_test
    ; --------------------------------------------------------------------------
    ; Step 1: Initialize Mixer to enable Channel A Tone, disable everything else
    ; --------------------------------------------------------------------------
    ; Register 7 is active-low: 
    ; Bit 0 = Tone A (0 = Enabled, 1 = Disabled)
    ; Bits 3-5 = Noise (1 = All Disabled)
    ; Bits 6-7 = I/O Ports direction (0 = Input, doesn't matter here)
    ; %11111110 ($FE) enables Channel A Tone only.
    
    LDA #R7_ENABLE
    STA psg_addr        ; Latch Register 7
    LDA #%11111110      ; Enable Channel A Tone
    STA psg_data        ; Write value to Mixer

    ; --------------------------------------------------------------------------
    ; Step 2: Set Channel A Volume to Maximum Static Level
    ; --------------------------------------------------------------------------
    ; Register 8 handles Channel A Amplitude.
    ; Bits 0-3 = Volume level (0 to 15)
    ; Bit 4   = Mode (0 = Static Volume, 1 = Hardware Envelope)
    
    LDA #R8_AMP_A
    STA psg_addr        ; Latch Register 8
    LDA #15             ; Max volume level (Static Mode)
    STA psg_data        ; Write value

    ; --------------------------------------------------------------------------
    ; Step 3: Set Channel A Pitch (Tone Period)
    ; --------------------------------------------------------------------------
    ; Formula: Tone Period = Master Clock / (16 * Desired Frequency)
    ; Assuming your independent oscillator is 2.0 MHz:
    ; To output an A4 (440 Hz): 2,000,000 / (16 * 440) = 284 (approx)
    ; 284 in hex = $011C
    ; Fine byte (R0) = $1C, Coarse byte (R1) = $01
    
    ; Write Fine Tune Byte
    LDA #R0_TONE_A_LO
    STA psg_addr        ; Latch Register 0
    LDA #$1C            ; Low byte of pitch period
    STA psg_data        ; Write data

    ; Write Coarse Tune Byte
    LDA #R1_TONE_A_HI
    STA psg_addr        ; Latch Register 1
    LDA #$01            ; High byte of pitch period
    STA psg_data        ; Write data

    ; --------------------------------------------------------------------------
    ; Step 4: Infinite Loop
    ; --------------------------------------------------------------------------
    ; The sound hardware will continuously latch and play the tone on its own
    ; until the registers are cleared, changed, or the system is RESET.
    
loop:
    BRA loop            ; 65C02 Branch Always (saves a byte over JMP)
.endproc

.segment "VECTORS"
	.word	0			; NMI vector address
	.word	main_test   ; RESET vector address
	.word	0			; IRQ/BRK vector address
