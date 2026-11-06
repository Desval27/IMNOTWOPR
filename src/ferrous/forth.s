; ============================================================================
; FORTH for IMNOTWOPR
; 
; Based/Inspired on/by 64FORTH By Tom Zimmer
; ============================================================================

.import acia_init
.import print_text
.import print_newline

TOS   = $60     ; $60: empty data-stack limit (X resets here)
N     = TOS+8   ; $68: volatile native operand workspace, eight bytes
IP    = N+8     ; $70: threaded instruction pointer (two bytes)
W     = IP+3    ; $73: current code-field address (two bytes)
UP    = W+2     ; $75: user-area base pointer (two bytes
XSAVE = UP+2    ; $77: saved data-stack X; also used as a scratch pointer
NXTMP = XSAVE+2 ; $79: indirect native dispatch address / scratch pointer

.segment "PROGRAM_CODE"
reset:
	sei				; Disable interrupts
	cld				; Clear decimal mode
	ldx	#$FF		; Set up stack pointer
	txs				;

;
; System Init
;
	; .. Init code goes here
	jsr acia_init

	cli				; Enable interrupts	

    jmp main


; ----------------------------------------------------------------------------
; Input: Y = index into error message table (0, 1, 2...)
; Output: A = LSB, X = MSB
print_error:
    tya
    asl a           ; A = index * 2
    tax             ; Transfer offset to X as a table index

    lda error_table, x       ; Load LSB into A
    pha                             ; Push LSB on stack
    inx
    lda error_table, x       ; Load MSB into A
    tax                             ; Transfer MSB into X
    pla                             ; Pull LSB back into A

    jsr print_text
    jsr print_newline
    rts

; ============================================================================
; Main Program Loop
; ============================================================================
main:
    ldy #0
    jsr print_error
    ldy #1
    jsr print_error
    ldy #2
    jsr print_error
    ldy #3
    jsr print_error
    ldy #4
    jsr print_error
    ldy #5
    jsr print_error

; Native cold-thread entry: point IP directly at COLD1 (the parameter
; thread), bypassing the COLD CFA
native_cold_entry:
    lda #>cold1
    sta IP+1
    lda #<cold1
    jmp common_restart

; Native warm-thread entry: point IP at WARM.  Both starts clear decimal mode
; and reset the hardware/data stack pointers before NEXT.
native_warm_entry:
    lda #>warm
    sta IP+1
    lda #<warm

; Common restart: install IP low byte and reset native/Forth stack state.
common_restart:
    sta IP
    ldx #$FF
    txs
    ldx #TOS
    jmp next

forever:
    jmp forever


; ============================================================================
; INNER INTERPRETER. 
; Fetch the next CFA from [IP] into W, then fetch its
; machine-code address from [W] into NXTMP.  Advance IP by two and JMP
; indirectly.  Y is zero at primitive entry.  W still names the CFA, so
; defining-word runtimes can locate their parameter field.
; ============================================================================
next:
    ldy #1
    lda (IP),y
    sta W+1
    dey
    lda (IP),y
    sta W
    lda (W),y
    sta NXTMP
    iny
    lda (W),y
    sta NXTMP+1
    dey
    clc
    lda IP
    adc #2          ; Advance to the next thread cell before executing this one
    sta IP
    bcc L816E
    inc IP+1
L816E:    
    jmp (NXTMP)     ; Jump to the native entry, with Y = 0 and W still the CFA






    .byte   $84,"col",$C4
    .word   0 ; L92CF ; CFA: Previous name field in this vocabulary chain
cold:
    .word   docol
cold1:
    ; stuff
    .word   0

warm:
    .word 0
    .byte 14
    .word 0
    .word 0

; ============================================================================
; DEFINING WORDS, CONSTANTS AND USER VARIABLES
; Dictionary: : [FORTH]; immediate (executes during compilation).
; Manual: Used in the form called a colon-definition : cccc ... ; Creates a 
; dictionary entry defining cccc as equivalent to the following sequence of
; FORTH word definitions '...' until 108 the next ';' or 'CODE'.  The
; compiling process is done by the text interpreter as long as STATE is
; non-zero.  Other details are that the CONTEXT vocabulary is set to the
; CURRENT vocabulary and that words with the precedence bit set (P) are
; executed rather than being compiled.  The : must be followed by a space, and
; the ; must be preceeded by a space.
; ============================================================================

; Colon runtime: save the caller IP high/low on the return stack, set IP=W+2
; (the parameter field), and execute NEXT. A colon definition is a stream of
; CFA cells, not native JSR instructions.
docol:
    lda IP+1
    pha
    lda IP
    pha
    clc
    lda W
    adc #2
    sta IP
    tya
    adc W+1
    sta IP+1
    jmp next


; Dictionary: USER [FORTH].
; Manual stack: ( n --- )
; Manual: A defining word used in the form: n USER cccc which creates a user
; variable cccc.  The parameter field of cccc contains n as a fixed offset
; relative to the user pointer register UP for this user variable.  When cccc
; is later executed, it places the sum of its offset and the user area base
; address on the stack as the storage address of that particular variable.
L87F5:
    .byte $84,"USE",$D2

; Dictionary: 0 [FORTH].
; Implementation: ( -- 0) Push the constant zero.
L8811:  
    .byte   $81,$B0
    .word   L87F5

.segment "RODATA"
; ----------------------------------------------------------------------------
; Error Messages
; ----------------------------------------------------------------------------
error_table:
    .word what
    .word stack_empty
    .word out_of_memory
    .word unknown_error
    .word has_bad_addr_mode
    .word block_range_error
    .word for_compiling_only
    .word for_executing_only
    .word improper_conditionals
    .word incomplete_definition
    .word this_word_protected
    .word use_only_when_loading
    .word specify_the_vocablulary

; Error Message Text
what:   
    .asciiz "what"
stack_empty:
    .asciiz "stack empty!"
out_of_memory:  
    .asciiz "out of memory"
unknown_error:
    .asciiz "unknown error"
has_bad_addr_mode:
    .asciiz "has bad addr mode"
block_range_error:
    .asciiz "block range error"
for_compiling_only:
    .asciiz "for compiling only"
for_executing_only:
    .asciiz "for executing only"
improper_conditionals:
    .asciiz "improper conditionals"
incomplete_definition:
    .asciiz "incomplete definition"
this_word_protected:
    .asciiz "this word protected"
use_only_when_loading:
    .asciiz "use only when loading"
specify_the_vocablulary:
    .asciiz "specify the vocabulary"




.segment "VECTORS"
	.word	0			; NMI vector address
	.word	reset		; RESET vector address
	.word	0			; IRQ/BRK vector address
