; ============================================================================
; FORTH for IMNOTWOPR
; 
; Based/Inspired on/by 64FORTH By Tom Zimmer
; ============================================================================

; LABEL CONVENTIONS
;   <word>_NFA names a dictionary header; reuse the existing CFA stem when
;   present (QSTAC_NFA / QSTAC). ASM_ and EDITOR_ distinguish words without
;   an established CFA name. Native branches and data tables describe their
;   purpose, not a historical ROM address.
;
; DICTIONARY FORMAT
;   NFA: flag/length byte, then name characters with bit 7 on the last byte.
;   Header bits: $80 marker, $40 immediate, $20 smudge, $1F length mask.
;   LFA: two-byte pointer to the preceding NFA in the vocabulary chain.
;   CFA: two-byte native entry pointer.  A Forth execution token is this
;        field's address.  PFA follows the CFA; its meaning depends on runtime.
;   DOCOL=thread, DCOCON=value, DOVAR=storage, DOUSE=user offset,
;   DOVECT=vector offset, DODOE=DOES> behavior pointer plus instance data.

;=============================================================================
; FORTH RAM EQUATES
;=============================================================================
USRINI	=	$0940		; Initial Forth UP (user area)
TIBINI	=	$0B80		; Initial terminal input buffer in this ROM
RAMVOC	=	$0840		; RAM copies of the four vocabulary definitions
RAMFTH	=	$0848		; Execution token of the RAM FORTH vocabulary
BUFONE	=	$7BFC		; Active screen buffer header; data starts two bytes later
; BUFLIM	=	$8000		; End of active buffer area (exclusive)
; BUFRAM	=	$C000		; Sixteen 1 KB backing slots; ROM/I/O must be banked out


.import __DICT_RAM_START__, __DICT_RAM_SIZE__
DICT_START = __DICT_RAM_START__
DICT_END = __DICT_RAM_START__ + __DICT_RAM_SIZE__
DICT_WORKSPACE = $100
STACK_BOTTOM = $10

TOS   = $60     ; $60: empty data-stack limit (X resets here)
N     = TOS+8   ; $68: volatile native operand workspace, eight bytes
IP    = N+8     ; $70: threaded instruction pointer (two bytes)
W     = IP+3    ; $73: current code-field address (two bytes)
UP    = W+2     ; $75: user-area base pointer (two bytes
XSAVE = UP+2    ; $77: saved data-stack X; also used as a scratch pointer
NXTMP = XSAVE+2 ; $79: indirect native dispatch address / scratch pointer

.import acia_init, print_chr, print_newline, acia_data, acia_status, acia_cmd

;=============================================================================
.segment "PROGRAM_CODE"
;=============================================================================

.macro REQUIRE_CELLS count
    cpx #TOS-count*2+1
    bcc :+
    lda #1
    jmp shell_error
:
.endmacro

.include "forth_shell.inc"

; CARTRIDGE HEADER ($8000-$8008). The C64 reset/NMI routines recognize the
; five-byte CBM80 signature and indirect through these cold/warm vectors.
; This is a 16 KB cartridge at $8000-$BFFF, not the soft-loaded PRG described
; in README.TXT.
CARTRIDGE_HEADER:
	.word	COLD_BOOT			; COLD BOOT
	.word	WARM_BOOT			; WARM BOOT
	.byte	$C3,$C2,$CD,$38,$30	; CARTRIDGE ID

WARM_BOOT:
    jmp shell_abort

reset:
COLD_BOOT:
    jmp shell_cold

; Compatibility alias for monitor users; the shell now waits for serial input.
main = serial_wait_key

; ----------------------------------------------------------------------------
; ORIGIN / INITIAL USER IMAGE. +ORIGIN indexes this ROM table. The first 12
; bytes are reserved; ORIG+12 starts the user initialization image. COLD
; copies 22 bytes for COLD or 14 for WARM to UP. These are startup values,
; not live variables.
ORIG:
	.word	0
	.word	0
	.word	0
	.word	0
	.word	0
	.word	0

; ----------------------------------------------------------------------------
; BOOTUP VARIABLES

	.word	$87B		; TOP WORD
	.word	0		; 
INITIAL_USER_POINTERS:
	.word	USRINI		; UP
	.word	TOS		; TOP OF STACK
	.word	$1FF		; TOP OF RETURN STACK
	.word	TIBINI		; TIB
	.word	$1F		; WIDTH
	.word	0		; 
	.word	DICT_START	; FENCE
	.word	DICT_START	; DP
	.word	$88C		; VOC-LINK


; ----------------------------------------------------------------------------
; Dictionary: VWORDS [FORTH].
; Manual stack: ( --- a1)
; Manual: This word returns the address all of the beginning of the initial
; value vector table in ROM.  See the section VECTORED WORDS for further
; information.
VWORDS_NFA:
    .byte   $86,"VWORD",$D3
    .word   0                   ; LFA: previous name field in this vocabulary chain
; DEFAULT VECTOR TABLE. The first twelve cells are CFAs, not machine-code
; entry addresses. They are followed by the capture-table pointer and initial
; file/device numbers. VRESET copies 28 bytes to UP+$32: the twelve
; I/O/compiler vectors, CTBL, and F#. The last value (D#) is outside that
; copy. The listing has comma at offset 20 and C-comma at 18; use these
; values rather than the reversed manual table.
VWORDS:
	.word	DOVAR	    ; CFA: variable; push the parameter-field address
	.word	PKEY		; 0
	.word	PEMIT		; 2
	.word	PQTER		; 4
	.word	PCRR		; 6
	.word	PCREAT		; 8
	.word	PNUMBE		; 10
	.word	PERROR		; 12
	.word	PDOT		; 14
	.word	PDFIND		; 16
	.word	PCCOM		; 18
	.word	PCOMMA		; 20
	.word	PRSLW		; 22
	.word	DEFAULT_KEY_TABLE		; 24
	.word	1		    ; 26
	.word	1		    ; 28

; KEY CAPTURE TABLE. Repeating PETSCII byte / Forth CFA pairs, terminated by
; a zero byte. PKEY scans CTBL, executes a matching action and retries when
; it returns zero. $94 appears twice; the earlier matching action can consume
; it. Codes $85/$86/$87/$88 are F1/F3/F5/F7; $89/$8A/$8B/$8C are F2/F4/F6/F8.
EDITOR_KEY_TABLE:
	.byte	$94		    ; 
	.word	EDITOR_MOVE

	.byte	$85		    ; F1
	.word	EDITOR_KEY_F1

	.byte	$86		    ; F3
	.word	EDITOR_KEY_F3

	.byte	$87		    ; F5
	.word	EDITOR_KEY_F5

	.byte	$1D		    ; RIGHT
	.word	EDITOR_KEY_RIGHT

	.byte	$9D		    ; LEFT
	.word	EDITOR_KEY_LEFT

	.byte	$11		    ; DOWN
	.word	EDITOR_KEY_DOWN

	.byte	$91		    ; UP
	.word	EDITOR_KEY_UP

	.byte	$13		    ; CTL-S
	.word	TOP

	.byte	$89		    ; F2
	.word	NN

	.byte	$8A		    ; F4
	.word	BB

	.byte	$88		    ; F7
	.word	PFF

	.byte	$8C		    ; F8
	.word	EDITOR_KEY_F8

	.byte	$94		    ; 
	.word	EDITOR_MOVE

	.byte	$8B		    ; F6
	.word	EDITOR_KEY_F6

	.byte	$B0		    ; CBM-A
	.word	EDITOR_KEY_F3

	.byte	$AE		    ; CBM-S
	.word	EDITOR_KEY_LEFT

	.byte	$AC		    ; CBM-D
	.word	EDITOR_KEY_RIGHT

	.byte	$BB		    ; CBM-B
	.word	EDITOR_KEY_F1

	.byte	$B1		    ; CBM-E
	.word	EDITOR_KEY_UP

	.byte	$B2		    ; CBM-R
	.word	BB

	.byte	$BD		    ; CBM-X
	.word	EDITOR_KEY_DOWN

	.byte	$BC		    ; CBM-C
	.word	NN

	.byte	$A5		    ; CBM-G
	.word	EDITOR_KEY_CBM_G

	.byte	$AD		    ; CBM-Z
	.word	EDITOR_KEY_CBM_Z

	.byte	$B7		    ; CBM-Y
	.word	EDITOR_KEY_CBM_Y

	.byte	0

; Default capture table: RETURN ($8D, shifted RETURN) invokes the
; copyright-message thread. Zero ends the table.
DEFAULT_KEY_TABLE:
	.byte	$8D
	.word	COPYRIGHT_THREAD
	.byte	0

; Anonymous colon definition used by the default key-capture table. PDOTQ
; consumes the following length byte and that many bytes, including any bytes
; which also resemble threaded code.
COPYRIGHT_THREAD:
	.word	DOCOL
	.word	CR
	.word	PDOTQ	; Print counted inline text; resume after its payload
	.byte	18
	.byte	"(C)1983 TOM ZIMMER"
	.word	CR
	.word	SEMIS	; Return to caller thread

; ============================================================================
; NATIVE CORE and THREADED EXECUTION
; ============================================================================

; ----------------------------------------------------------------------------
; Dictionary: (MATCH) [FORTH].
; Manual stack: (a1/a2/n1 --- f1 )
; Manual: An assembly language MATCH primitive. Given the addresses of
; strings of characters (a1 and a2), and a match length of characters (n1),
; returns boolean f1 as true if the strings are the same character sequence.
; Otherwise, returns a boolean false.
PMATCH_NFA:
	.byte	$87,"(MATCH",$A9
	.word	VWORDS_NFA	; LFA: previous name field in this vocabulary chain
; IMPLEMENTATION ( a1 a2 n -- flag ). Only the low byte of n is used. Compare
; backwards through n bytes using XSAVE/XSAVE+1 and NXTMP/NXTMP+1 as
; pointers. A zero length returns false in this implementation. Replace a1
; with 0 or 1 and discard a2/n.
PMATCH:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 3
	ldy	0,X
	beq	PMATCH_FALSE
	lda	2,X
	sta	NXTMP
	lda	3,X
	sta	NXTMP+1
	lda	4,X
	sta	XSAVE
	lda	5,X
	sta	NXTMP-1
; Compare one byte from each string, working toward offset zero.
PMATCH_COMPARE_BYTE:
	dey
	lda	(NXTMP),Y
	cmp	(XSAVE),Y
	bne	PMATCH_FALSE
	cpy	#0
	bne	PMATCH_COMPARE_BYTE
	lda	#1
	sta	4,X
	bne	PMATCH_FINISH
; Mismatch or zero length: return false.
PMATCH_FALSE:
	lda	#0
	tay
	sta	4,X
PMATCH_FINISH:
	tya
	sta	5,X
	jmp	POPTWO

; ----------------------------------------------------------------------------
; Dictionary: LIT [FORTH].
; Manual stack: ( --- n )
; Manual: Within a colon-definition, LIT is automatically compiled before
; each 16 bit literal number encountered in input text. Later execution of
; LIT causes the contents of the next dictionary address to be pushed to the
; stack.
LIT_NFA:
	.byte	$83,"LI",$D4
	.word	PMATCH_NFA	; LFA: previous name field in this vocabulary chain
; LIT ( -- cell ): read the two bytes following this token in the thread. IP
; already points at the literal, and Y=0 on entry. The low byte is staged on
; the hardware stack; A carries the high byte to PUSH.
LIT:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
	lda	(IP),Y
	pha
	inc	IP
	bne	LIT_HIGH_BYTE
	inc	IP+1
LIT_HIGH_BYTE:
	lda	(IP),Y
; Advance IP past the final literal byte; carry propagates across pages.
LIT_ADVANCE_AND_PUSH:
	inc	IP
	bne	PUSH
	inc	IP+1

; Shared tail: allocate a new 16-bit data-stack cell by decreasing X twice.
; Entry requires high byte in A and low byte on top of the hardware stack.
PUSH:
    cpx #STACK_BOTTOM+2
    bcs :+
    lda #27
    jmp shell_error
:
	dex
	dex

; Shared tail: replace the cell at X with A:pla (high:low), then fall into
; NEXT. PUT does not allocate a cell.
PUT:
	sta	1,X
	pla
	sta	0,X

; INNER INTERPRETER. Fetch the next CFA from [IP] into W, then fetch its
; machine-code address from [W] into NXTMP. Advance IP by two and jmp
; indirectly. Y is zero at primitive entry. W still names the CFA, so
; defining-word runtimes can locate their parameter fields.
NEXT:
    lda break_requested
    beq :+
    jmp shell_break
:   lda rx_overflow
    beq :+
    lda #28
    jmp shell_error
:   cpx #TOS+1
    bcc :+
    lda #1
    jmp shell_error
:   cpx #STACK_BOTTOM
    bcs :+
    lda #27
    jmp shell_error
:   stx XSAVE
    tsx
    cpx #$20
    ldx XSAVE
    bcs :+
    lda #29
    jmp shell_error
:
	ldy	#1
	lda	(IP),Y
	sta	W+1
	dey
	lda	(IP),Y
	sta	W
	lda	(W),Y
	sta	NXTMP
	iny
	lda	(W),Y
	sta	NXTMP+1
	dey
	clc
	lda	IP
	adc	#2	; Advance to the next thread cell before executing this one
	sta	IP
	bcc	NEXT_DISPATCH
	inc	IP+1
NEXT_DISPATCH:
	jmp	(NXTMP)	; Jump to the native entry, with Y=0 and W still the CFA

; ----------------------------------------------------------------------------
; Dictionary: CLIT [FORTH].
; Implementation: ( -- u ) Push an inline byte as a cell and advance IP by
; one.
CLIT_NFA:
	.byte	$84,"CLI",$D4
	.word	LIT_NFA	; LFA: previous name field in this vocabulary chain
; CLIT ( -- byte ): like LIT, but consume one inline byte and push a
; zero-extended cell. Threads need not be word-aligned; do not insert
; alignment padding.
CLIT:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
	lda	(IP),Y
	pha
	tya
	beq	LIT_ADVANCE_AND_PUSH

; Native helper, entered with A=number of stack cells and Y=0. Copy 2*A bytes
; from the data stack into N upward, advancing X to consume them. N-1 is the
; byte count; Y is restored to zero. The topmost input becomes N/N+1.
SETUP:
	asl	A
	sta	N-1
SETUP_COPY_BYTE:
	lda	0,X
	sta	N,Y
	inx
	iny
	cpy	N-1
	bne	SETUP_COPY_BYTE
	ldy	#0
	rts

; ----------------------------------------------------------------------------
; Dictionary: EXECUTE [FORTH].
; Stack (from code): ( cfa -- )
; Manual: Executes the definition whose field address is on the stack. The
; code field address is also called the compilation address.
EXEC_NFA:
	.byte	$87,"EXECUT",$C5
	.word	CLIT_NFA	; LFA: previous name field in this vocabulary chain
; EXECUTE ( cfa -- ): pop a code-field address into W, fetch [W] and dispatch
; without advancing IP. The executed word returns to the already pending
; thread.
EXEC:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 1
	lda	0,X
	sta	W
	lda	1,X
	sta	W+1
	inx
	inx
	ldy	#0
; Dispatch W as a CFA; shared by EXECUTE and DOVEC.
EXEC_DISPATCH:
	lda	(W),Y
	sta	NXTMP
	iny
	lda	(W),Y
	sta	NXTMP+1
	dey
	jmp	(NXTMP)

; ----------------------------------------------------------------------------
; Dictionary: VECTOR [FORTH].
; Manual stack: ( n1 --- (text) )
; Manual: A defining word used in the form: n1 VECTOR (text) to create a word
; (text) which when executed will itself execute the contents of the n1
; vectored routine in the I/O table. User created vectors must start at value
; 30 decimal, and must not be higher than 50. The vector position in the I/O
; table must be initialized before the new vector is executed or a crash will
; result.
DOVEC_NFA:
	.byte	$86,"VECTO",$D2
	.word	EXEC_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	CONST
	.word	PSCOD
; Vector runtime: add the one-byte parameter to UP+$32, fetch the replacement
; CFA from that user-area slot, and use EXECUTE dispatch. The table therefore
; contains CFAs rather than raw 6502 entry points.
DOVEC:
	ldy	#2
	clc
	lda	(W),Y
	adc	#$32
	adc	UP
	sta	W
	lda	#0
	tay
	adc	UP+1
	sta	W+1
	lda	(W),Y
	pha
	iny
	lda	(W),Y
	dey
	sta	W+1
	pla
	sta	W
	jmp	EXEC_DISPATCH

; ----------------------------------------------------------------------------
; Dictionary: BRANCH [FORTH].
; Manual: The run-time procedure to unconditionally branch. An in-line offset
; is added to the interpretive pointer to IP to branch ahead or back. BRANCH
; is compiled by ELSE, AGAIN, REPEAT.
BRAN_NFA:
	.byte	$86,"BRANC",$C8
	.word	DOVEC_NFA	; LFA: previous name field in this vocabulary chain
; Runtime branch: add the signed 16-bit inline displacement to IP. The origin
; is the address of the displacement itself, not the following token.
; Arithmetic wraps modulo 65536.
BRAN:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
	clc
	lda	(IP),Y
	adc	IP
	pha
	iny
	lda	(IP),Y
	adc	IP+1
	sta	IP+1
	pla
	sta	IP
	jmp	NEXT

; ----------------------------------------------------------------------------
; Dictionary: 0BRANCH [FORTH].
; Manual stack: ( f --- )
; Manual: The run-time procedure to branch conditionally. If f is false
; (zero), the following in-line parameter is added to the interpretive
; pointer to branch ahead or back. Compiled by IF, UNTIL, and WHILE.
ZBRAN_NFA:
	.byte	$87,"0BRANC",$C8
	.word	BRAN_NFA	; LFA: previous name field in this vocabulary chain
; Runtime conditional branch: consume one flag. $FE,X/$FF,X deliberately wrap
; in zero page to read the cell just popped. Nonzero skips the two-byte
; displacement; zero shares BRANCH.
ZBRAN:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 1
	inx
	inx
	lda	$FE,X
	ora	$FF,X
	beq	BRAN+2

; Skip one inline 16-bit operand, carrying into IP+1, and resume NEXT.
BUMP:
	clc
	lda	IP
	adc	#2
	sta	IP
	bcc	BUMP_DONE
	inc	IP+1
BUMP_DONE:
	jmp	NEXT

; ----------------------------------------------------------------------------
; Dictionary: (LOOP) [FORTH].
; Stack (from code): ( -- ) Update or remove the return-stack loop frame.
; Manual: The run-time procedure compiled by LOOP which increments the loop
; index and tests for loop completion. See LOOP.
PLOOP_NFA:
	.byte	$86,"(LOOP",$A9
	.word	ZBRAN_NFA	; LFA: previous name field in this vocabulary chain
; Loop frame on hardware stack, relative to S: +1/+2=index, +3/+4=limit. Save
; data-stack X before tsx. Increment the index, compare to limit, then either
; take the inline backward branch or discard the four-byte frame and skip the
; offset.
PLOOP:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
	stx	XSAVE
	tsx
	inc	$101,X
	bne	PL1
	inc	$102,X

; Compare limit-index-1; carry is deliberately clear before sbc.
PL1:
	clc
	lda	$103,X
	sbc	$101,X
	lda	$104,X
	sbc	$102,X

; Use comparison sign to choose continuation; restore Forth X first.
PL2:
	ldx	XSAVE
	asl	A
	bcc	BRAN+2
	pla
	pla
	pla
	pla
	jmp	BUMP

; ----------------------------------------------------------------------------
; Dictionary: (+LOOP) [FORTH].
; Manual stack: ( n --- )
; Manual: The run-time procedure compiled by +LOOP, which increments the loop
; index by n and tests for loop completion. See +LOOP.
PPLOO_NFA:
	.byte	$87,"(+LOOP",$A9
	.word	PLOOP_NFA	; LFA: previous name field in this vocabulary chain
; Consume the signed increment and add it to the hardware-stack loop index.
; Its sign chooses the comparison direction. PL2 restores data-stack X and
; shares loop termination with (LOOP).
PPLOO:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 1
	inx
	inx
	stx	XSAVE
	lda	$FF,X
	pha
	pha
	lda	$FE,X
	tsx
	inx
	inx
	clc
	adc	$101,X
	sta	$101,X
	pla
	adc	$102,X
	sta	$102,X
	pla
	bpl	PL1
	clc
	lda	$101,X
	sbc	$103,X
	lda	$102,X
	sbc	$104,X
	jmp	PL2

; ----------------------------------------------------------------------------
; Dictionary: (DO) [FORTH].
; Stack (from code): ( limit start -- ) Return stack: ( -- limit start ).
; Manual: The run-time procedure compiled by DO which moves the loop control
; parameters to the return stack. See DO.
PDO_NFA:
	.byte	$84,"(DO",$A9
	.word	PPLOO_NFA	; LFA: previous name field in this vocabulary chain
; (DO) ( limit start -- ): push limit high/low followed by index high/low
; onto the return stack. The index is nearest its top, so I can share the R
; fetch routine.
PDO:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 2
	lda	3,X
	pha
	lda	2,X
	pha
	lda	1,X
	pha
	lda	0,X
	pha

; Shared native tail: discard two data-stack cells (four bytes) by falling
; through POP.
POPTWO:
    REQUIRE_CELLS 2
	inx
	inx

; Shared native tail: discard one data-stack cell (two bytes), then dispatch
; NEXT.
POP:
    REQUIRE_CELLS 1
	inx
	inx
	jmp	NEXT

; ----------------------------------------------------------------------------
; Dictionary: I [FORTH].
; Manual stack: ( --- n )
; Manual: Copies the index of the current DO...LOOP counter to the
; computation stack.
I_NFA:
	.byte	$81,$C9
	.word	PDO_NFA	; LFA: previous name field in this vocabulary chain
I:
	.word	R+2

; ----------------------------------------------------------------------------
; Dictionary: DIGIT [FORTH].
; Manual stack: ( c n1 --- n2 tf )
; Manual: ( c n1 --- ff ) Converts the ASCII character c (using base n1) to
; its binary equivalent n2, accompanied by a true flag. If the conversion is
; invalid, leaves only a false flag.
DIGIT_NFA:
	.byte	$85,"DIGI",$D4
	.word	I_NFA	; LFA: previous name field in this vocabulary chain
; Convert the low-byte character using decimal digits or uppercase letters.
; On success return the digit and true; on failure return false. This
; byte-oriented primitive compares against the low byte of the requested
; base.
DIGIT:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 2
	sec
	lda	2,X
	sbc	#'0'
	bmi	DIGIT_INVALID
	cmp	#10
	bmi	DIGIT_CHECK_BASE
	sec
	sbc	#7
	cmp	#10
	bmi	DIGIT_INVALID
DIGIT_CHECK_BASE:
	cmp	0,X
	bpl	DIGIT_INVALID
	sta	2,X
	lda	#1
	pha
	tya
	jmp	PUT
DIGIT_INVALID:
	tya
	pha
	jmp	BINARY_RESULT

; ----------------------------------------------------------------------------
; Dictionary: (FIND) [FORTH].
; Manual stack: ( a1 a2 --- pta b tf ) (ok)
; Manual: ( a1 a2 --- ff ) (bad) 103 Searches the dictionary starting at the
; name field address a2, matching to the text at address a1. Returns the
; parameter field address, length in bytes of name field, and boolean true for
; a good match. If no match is found, only a boolean false is left.
PFIND_NFA:
	.byte	$86,"(FIND",$A9
	.word	DIGIT_NFA	; LFA: previous name field in this vocabulary chain
; Dictionary search: SETUP puts starting NFA in N and counted-string pointer
; in N+2. Mask $3F compares length and smudge state while ignoring immediate
; bit. Names end with bit 7 set; shifting the XOR ignores that bit for
; comparison. On success return PFA, the header flag/length byte, and 1;
; otherwise follow the LFA until zero.
PFIND:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 2
	lda	#2
	jsr	SETUP
	stx	XSAVE
; Try the next dictionary header (N points at its NFA).
PFIND_HEADER:
	ldy	#0
	lda	(N),Y
	eor	(N+2),Y
	and	#$3F
	bne	PFIND_SKIP_NAME
PFIND_COMPARE_NAME:
	iny
	lda	(N),Y
	eor	(N+2),Y
	asl	A
	bne	PFIND_MISMATCH
	bcc	PFIND_COMPARE_NAME
	ldx	XSAVE
	dex
	dex
	dex
	dex
	clc
	tya
	adc	#5
	adc	N
	sta	2,X
	ldy	#0
	tya
	adc	N+1
	sta	3,X
	sty	1,X
	lda	(N),Y
	sta	0,X
	lda	#1
	pha
	jmp	PUSH

PFIND_MISMATCH:
	bcs	PFIND_FOLLOW_LINK
; Skip remaining name bytes until the high-bit end marker.
PFIND_SKIP_NAME:
	iny
	lda	(N),Y
	bpl	PFIND_SKIP_NAME
; Read the two-byte link following the name; zero ends the chain.
PFIND_FOLLOW_LINK:
	iny
	lda	(N),Y
	tax
	iny
	lda	(N),Y
	sta	N+1
	stx	N
	ora	N
	bne	PFIND_HEADER
	ldx	XSAVE
	lda	#0
	pha
	jmp	PUSH

; ----------------------------------------------------------------------------
; Dictionary: ENCLOSE [FORTH].
; Manual stack: ( a c --- ) ( a1 n1 n2 n3 )
; Manual: The text scanning primitive used by WORD. From the text address a1
; and an ASCII delimiting character c is determined the byte offset to the
; first non-delimiter character n1, the offset to the first character
; delimiter after the text n2, and the offset to the first character not
; included. This procedure will not proceed past an ASCII 'null", treating it
; as an unconditional delimiter.
ENCL_NFA:	
	.byte	$87,"ENCLOS",$C5
	.word	PFIND_NFA	; LFA: previous name field in this vocabulary chain
; Scan from a1 past leading delimiter bytes, then through the token until a
; delimiter or NUL. Return the original address and three offsets (start,
; end, next). Y and the pointer high byte cooperate to scan beyond one page.
ENCL:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 2
	lda	#2
	jsr	SETUP
	txa
	sec
	sbc	#8
	tax
	sty	3,X
	sty	1,X
	dey
	dec	N+3
	dec	1,X
ENCL_SKIP_DELIMITER:
	iny
	bne	ENCL_CHECK_DELIMITER
	inc	N+3
	inc	1,X
ENCL_CHECK_DELIMITER:
	lda	(N+2),Y
	cmp	N
	beq	ENCL_SKIP_DELIMITER
	sty	4,X
	lda	1,X
	sta	5,X
ENCL_SCAN_WORD:
	lda	(N+2),Y
	bne	ENCL_RECORD_END
	sty	2,X
	sty	0,X
	lda	1,X
	sta	3,X
	tya
	cmp	4,X
	bne	ENCL_DONE
	lda	1,X
	cmp	5,X
	bne	ENCL_DONE
	inc	2,X
	bne	ENCL_DONE
	inc	3,X
ENCL_DONE:
	jmp	NEXT

ENCL_RECORD_END:
	pha
	sty	2,X
	lda	1,X
	sta	3,X
	iny
	bne	ENCL_CHECK_WORD_END
	inc	1,X
	inc	N+3
ENCL_CHECK_WORD_END:
	pla
	cmp	N
	bne	ENCL_SCAN_WORD
	sty	0,X
	jmp	NEXT

; ----------------------------------------------------------------------------
; Dictionary: EMIT [FORTH].
; Manual stack: ( c1 --- )
; Manual: Sends the character c1 to the selected output device. OUT is
; incremented for each character output. The output device is determined by
; the most recent use of the SYSTEM call CHKOUT. Normally characters are sent
; to the video screen. This is a vectored word.
EMIT_NFA:
	.byte	$84,"EMI",$D4
	.word	ENCL_NFA	; LFA: previous name field in this vocabulary chain
EMIT:
	.word	DOVEC	; CFA: vectored word; dispatch through UP+$32+offset
	.byte	2	; Vector byte offset 2 from I/O (UP+$32)

PEMIT:
	.word	DOCOL
	.word	SERIAL_EMIT
	.word	ONE
	.word	OUT
	.word	PSTOR
	.word	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: KEY [FORTH].
; Manual stack: ( --- n1 )
; Manual: Returns value n1, the ASCII key value of the key pressed on the
; keyboard. Before returning with the key value, the 132 key pressed is
; checked to see if it is in the key capture table. If it is, the associated
; function is executed, and another key is obtained from the keyboard. This
; is a vectored word.
KEY_NFA:
	.byte	$83,"KE",$D9
	.word	EMIT_NFA	; LFA: previous name field in this vocabulary chain
KEY:
	.word	DOVEC	; CFA: vectored word; dispatch through UP+$32+offset
	.byte	0	; Vector byte offset 0 from I/O (UP+$32)

; Default KEY blocks on the interrupt-buffered ACIA input queue.
PKEY:
    .word *+2
    jsr serial_key
    jmp PUSH0A

; ----------------------------------------------------------------------------
; Dictionary: ?TERMINAL [FORTH].
; Manual stack: ( --- n1 )
; Manual: A modified version of the fig-FORTH word of the same name. If a key
; is pressed, the value of the key pressed n1 is returned. If no key was
; pressed, zero is returned. This is a vectored word.
QTER_NFA:
	.byte	$89,"?TERMINA",$CC
	.word	KEY_NFA	; LFA: previous name field in this vocabulary chain
QTER:
	.word	DOVEC	; CFA: vectored word; dispatch through UP+$32+offset
	.byte	4	; Vector byte offset 4 from I/O (UP+$32)

; Default ?TERMINAL consumes one queued byte, or returns zero if empty.
PQTER:
    .word *+2
    jsr serial_try_key
    bcs :+
    lda #0
:   jmp PUSH0A

; ----------------------------------------------------------------------------
; Dictionary: CR [FORTH].
; Manual: Transmits a carriage return and line feed to the selected output
; device. This is a vectored word.
CR_NFA:
	.byte	$82,"C",$D2
	.word	QTER_NFA	; LFA: previous name field in this vocabulary chain
CR:
	.word	DOVEC	; CFA: vectored word; dispatch through UP+$32+offset
	.byte	6	; Vector byte offset 6 from I/O (UP+$32)

PCRR:
    .word *+2
    jsr print_newline
    stz USRINI+$1A
    stz USRINI+$1B
    jmp NEXT

; ----------------------------------------------------------------------------
; Dictionary: VRESET [FORTH].
; Manual stack: ( --- )
; Manual: Resets the I/O vector table, from the VWORDS vector table, to
; restore the state of the system I/O vectors. This word is executed by
; ABORT. The value of D# and F# are also reset by this word.
VRESET_NFA:
	.byte	$86,"VRESE",$D4
	.word	CR_NFA	; LFA: previous name field in this vocabulary chain
VRESET:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	VWORDS
	.word	IO
	.word	CLIT	; Push following inline byte, zero-extended
	.byte	28
	.word	CMOVE
	.word	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: CMOVE [FORTH].
; Manual stack: ( from to count --- )
; Manual: Moves the specified quantity of bytes beginning at address from to
; address to. The contents of address from is moved first proceeding toward
; high memory. Further specification is necessary on word processing
; computers.
CMOVE_NFA:	
    .byte	$85,"CMOV",$C5
	.word	VRESET_NFA	; LFA: previous name field in this vocabulary chain
; Forward byte copy ( src dst count -- ). SETUP lays out count at N,
; destination at N+2, source at N+4. Y traverses each page and pointer high
; bytes advance on wrap. Overlap is safe only when forward copying will not
; overwrite unread source bytes.
CMOVE:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 3
	lda	#3
	jsr	SETUP
; Test remaining count against Y, decrementing the high count on each match.
CMOVE_CHECK_COUNT:
	cpy	N
	bne	CMOVE_COPY_BYTE
	dec	N+1
	bpl	CMOVE_COPY_BYTE
	jmp	NEXT

; Copy one byte; wrap Y and increment both pointer high bytes at page end.
CMOVE_COPY_BYTE:
	lda	(N+4),Y
	sta	(N+2),Y
	iny
	bne	CMOVE_CHECK_COUNT
	inc	N+5
	inc	N+3
	jmp	CMOVE_CHECK_COUNT

; ----------------------------------------------------------------------------
; Dictionary: SMOVE [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( a1/a2 --- a1/a2 )
; Manual: This word moves 40 characters from address a1 to 143 address a2,
; and modifies the date during the move, from ASCII to the Commodore
; equivalent value to show properly on the screen. Address a1 and a2 are
; returned unmodified. Address a2 is normally on the Commodore 64's screen,
; in the range 1024 to 2040, and address a1 is normally somewhere within the
; FORTH screen buffer. When this word is used in a DO LOOP, a full 24 line
; screen can be moved from anywhere in memory, to the screen in less than 50
; milli-seconds. Pronounced "screen move."
SMOVE_NFA:
	.byte	$85,"SMOV",$C5
	.word	CMOVE_NFA	; LFA: previous name field in this vocabulary chain
; Display helper: copy exactly 40 bytes backwards, subtracting 64 from
; character values >=64 to form screen codes. Restoring XSAVE means the two
; address arguments remain on the data stack.
SMOVE:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: U* [FORTH].
; Manual stack: ( u1 u2 --- ud )
; Manual: Leaves the unsigned double number product of two unsigned numbers.
USTAR_NFA:
	.byte	$82,"U",$AA
	.word	SMOVE_NFA	; LFA: previous name field in this vocabulary chain
; Unsigned 16x16 multiply producing a 32-bit result in the two input cells.
; Sixteen shift/add iterations; N holds a saved multiplicand. The high result
; cell is at the top of stack.
USTAR:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 2
	lda	2,X
	sta	N
	sty	2,X
	lda	3,X
	sta	N+1
	sty	3,X
	ldy	#16
; One multiplication bit: shift partial product, add saved multiplicand if
; needed.
USTAR_SHIFT_ADD:
	asl	2,X
	rol	3,X
	rol	0,X
	rol	1,X
	bcc	USTAR_NEXT_BIT
	clc
	lda	N
	adc	2,X
	sta	2,X
	lda	N+1
	adc	3,X
	sta	3,X
	bcc	USTAR_NEXT_BIT
	inc	0,X
	bne	USTAR_NEXT_BIT
	inc	1,X
USTAR_NEXT_BIT:
	dey
	bne	USTAR_SHIFT_ADD
	jmp	NEXT

; ----------------------------------------------------------------------------
; Dictionary: U/ [FORTH].
; Manual stack: ( ud u1 --- u2 u3)
; Manual: Leaves the unsigned remainder of u2 and unsigned quotient u3 from
; the unsigned double dividend ud and unsigned divisor u1.
USLAS_NFA:
	.byte	$82,"U",$AF
	.word	USTAR_NFA	; LFA: previous name field in this vocabulary chain
; Unsigned restoring division: divide a 32-bit dividend by a 16-bit divisor
; over sixteen iterations. Leaves remainder below quotient. There is no
; explicit divide-by-zero or quotient-overflow check here.
USLAS:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 3
    lda 0,x
    ora 1,x
    bne :+
    lda #31
    jmp shell_error
:   sty N+1
	lda	4,X
	ldy	2,X
	sty	4,X
	asl	A
	sta	2,X
	lda	5,X
	ldy	3,X
	sty	5,X
	rol	A
	sta	3,X
	lda	#16
	sta	N
; One division bit: shift remainder, trial-subtract divisor, retain
; successful subtraction.
USLAS_TRIAL_SUBTRACT:
	rol	4,X
	rol	5,X
	rol	N+1
	sec
	lda	4,X
	sbc	0,X
	tay
	lda	5,X
	sbc	1,X
	pha
	lda	N+1
	sbc	#0
	lda	#0
	sta	N+1
	pla
	bcc	USLAS_SHIFT_QUOTIENT
	sty	4,X
	sta	5,X
; Shift success/failure carry into quotient; repeat for sixteen bits.
USLAS_SHIFT_QUOTIENT:
	rol	2,X
	rol	3,X
	dec	N
	bne	USLAS_TRIAL_SUBTRACT
	jmp	POP

; ----------------------------------------------------------------------------
; Dictionary: and [FORTH].
; Stack (from code): ( x1 x2 -- x3 )
; Manual: Leaves the bitwise logical and of n1 and n2 as n3.
ANDD_NFA:
	.byte	$83,"AN",$C4
	.word	USLAS_NFA	; LFA: previous name field in this vocabulary chain
ANDD:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 2
	lda	0,X
	and	2,X
	pha
	lda	1,X
	and	3,X
BINARY_RESULT:
	inx
	inx
	jmp	PUT

; ----------------------------------------------------------------------------
; Dictionary: OR [FORTH].
; Stack (from code): ( x1 x2 -- x3 )
; Manual: Leaves the bit-wise logical or of two 16-bit values.
ORR_NFA:
	.byte	$82,"O",$D2
	.word	ANDD_NFA	; LFA: previous name field in this vocabulary chain
ORR:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 2
	lda	0,X
	ora	2,X
	pha
	lda	1,X
	ora	3,X
	jmp	BINARY_RESULT

; ----------------------------------------------------------------------------
; Dictionary: XOR [FORTH].
; Stack (from code): ( x1 x2 -- x3 )
; Manual: Leaves the bitwise logical exclusive-or of the two values.
XORR_NFA:
	.byte	$83,"XO",$D2
	.word	ORR_NFA	; LFA: previous name field in this vocabulary chain
XORR:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 2
	lda	0,X
	eor	2,X
	pha
	lda	1,X
	eor	3,X
	jmp	BINARY_RESULT

; ----------------------------------------------------------------------------
; Dictionary: SP@ [FORTH].
; Manual stack: ( --- a )
; Manual: Returns the address of the stack position to the top of the stack,
; as it was before SP@ was executed. (e.g. 1 2 SP@ @ ... would type 2 2 1 ).
SPAT_NFA:
	.byte	$83,"SP",$C0
	.word	XORR_NFA	; LFA: previous name field in this vocabulary chain
SPAT:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
	txa

PUSH0A:
	pha
	lda	#0
	jmp	PUSH

; ----------------------------------------------------------------------------
; Dictionary: SP! [FORTH].
; Stack (from code): ( ... -- ) Reset data stack to S0.
; Manual: Clears the stack.
SPSTO_NFA:
	.byte	$83,"SP",$A1
	.word	SPAT_NFA	; LFA: previous name field in this vocabulary chain
; Reset X from the initial stack pointer at UP+6. This SP! does not consume a
; caller-supplied pointer; it resets the data stack.
SPSTO:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
	ldy	#6
	lda	(UP),Y
	tax
	jmp	NEXT

; ----------------------------------------------------------------------------
; Dictionary: RP! [FORTH].
; Stack (from code): ( -- ) Reset return stack to R0.
; Manual: A computer dependent procedure to initialize the return stack
; pointer.
RPSTO_NFA:
	.byte	$83,"RP",$A1
	.word	SPSTO_NFA	; LFA: previous name field in this vocabulary chain
; Reset the hardware stack pointer from UP+8 while preserving data-stack X.
; Any outstanding return addresses / loop frames are discarded.
RPSTO:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
	stx	XSAVE
	ldy	#8
	lda	(UP),Y
	tax
	txs
	ldx	XSAVE
	jmp	NEXT

; ----------------------------------------------------------------------------
; Dictionary: ;S [FORTH].
; Manual: Stops interpretation of a screen. ;S is also the run-time word
; compiled at the end of a colon-definition which returns execution to the
; calling procedure.
SEMIS_NFA:
	.byte	$82,";",$D3
	.word	RPSTO_NFA	; LFA: previous name field in this vocabulary chain
; Return from a colon definition: restore IP low/high from the hardware
; return stack and enter NEXT. This is the Forth return operation, not a 6502
; rts.
SEMIS:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
	pla
	sta	IP
	pla
	sta	IP+1
	jmp	NEXT

; ----------------------------------------------------------------------------
; Dictionary: LEAVE [FORTH].
; Manual: Forces termination of a DO-LOOP at the next opportunity by setting
; the loop limit equal to the current value of the index. The index itself
; remains unchanged, and execution proceeds normally until LOOP or +LOOP is
; encountered.
LEAVE_NFA:
	.byte	$85,"LEAV",$C5
	.word	SEMIS_NFA	; LFA: previous name field in this vocabulary chain
; Copy current loop index into its limit. Execution continues through the
; loop body until its next (LOOP)/(+LOOP) test; this is the older fig-Forth
; LEAVE behavior.
LEAVE:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
	stx	XSAVE
	tsx
	lda	$101,X
	sta	$103,X
	lda	$102,X
	sta	$104,X
	ldx	XSAVE
	jmp	NEXT

; ----------------------------------------------------------------------------
; Dictionary: >R [FORTH].
; Manual stack: ( n --- )
; Manual: Removes a number from the computation stack and places as the most
; accessible on the return stack. Use should be balanced with R> in the same
; definition.
TOR_NFA:
	.byte	$82,">",$D2
	.word	LEAVE_NFA	; LFA: previous name field in this vocabulary chain
; Move a cell to the hardware return stack, high byte first. This stack also
; holds colon return IPs, loop frames and temporary native jsr/pha data.
TOR:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 1
	lda	1,X
	pha
	lda	0,X
	pha
	jmp	POP

; ----------------------------------------------------------------------------
; Dictionary: R> [FORTH].
; Manual stack: ( --- n )
; Manual: Removes the top value from the return stack and leaves it on the
; computation stack. See >R and R.
RFROM_NFA:
	.byte	$82,"R",$BE
	.word	TOR_NFA	; LFA: previous name field in this vocabulary chain
RFROM:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
	dex
	dex
	pla
	sta	0,X
	pla
	sta	1,X
	jmp	NEXT

; ----------------------------------------------------------------------------
; Dictionary: R [FORTH].
; Manual stack: ( --- n )
; Manual: Copies the top of the return stack to the computation stack.
R_NFA:
	.byte	$81,$D2
	.word	RFROM_NFA	; LFA: previous name field in this vocabulary chain
; Fetch the top return-stack cell without removing it. I uses the same native
; entry (R+2) while a loop index is on top.
R:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
	stx	XSAVE
	tsx
	lda	$101,X
	pha
	lda	$102,X
	ldx	XSAVE
	jmp	PUSH

; ----------------------------------------------------------------------------
; Dictionary: 0= [FORTH].
; Stack (from code): ( x -- flag )
; Manual: Leaves a true flag if the number is equal to zero; otherwise leaves
; a false flag.
ZEQU_NFA:
	.byte	$82,"0",$BD
	.word	R_NFA	; LFA: previous name field in this vocabulary chain
ZEQU:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 1
	lda	0,X
	ora	1,X
	sty	1,X
	bne	ZEQU_STORE_FLAG
	iny
ZEQU_STORE_FLAG:
	sty	0,X
	jmp	NEXT

; ----------------------------------------------------------------------------
; Dictionary: 0< [FORTH].
; Stack (from code): ( n -- flag )
; Manual: Leaves a true flag if the number is less than zero (negative);
; otherwise leaves a false flag.
ZLESS_NFA:
	.byte	$82,"0",$BC
	.word	ZEQU_NFA	; LFA: previous name field in this vocabulary chain
ZLESS:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 1
	asl	1,X
	tya
	rol	A
	sty	1,X
	sta	0,X
	jmp	NEXT

; ----------------------------------------------------------------------------
; Dictionary: + [FORTH].
; Manual stack: ( n1 n2 --- sum )
; Manual: Leaves the sum of n1 + n2 on the stack.
PLUS_NFA:
	.byte	$81,$AB
	.word	ZLESS_NFA	; LFA: previous name field in this vocabulary chain
PLUS:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 2
	clc
	lda	0,X
	adc	2,X
	sta	2,X
	lda	1,X
	adc	3,X
	sta	3,X
	jmp	POP

; ----------------------------------------------------------------------------
; Dictionary: D+ [FORTH].
; Stack (from code): ( d1 d2 -- d3 )
; Manual: Leaves the double number sum of two double numbers.
DPLUS_NFA:
	.byte	$82,"D",$AB
	.word	PLUS_NFA	; LFA: previous name field in this vocabulary chain
; Add low cells first, then high cells with carry propagated across all four
; bytes. Doubles occupy low-cell then high-cell order, with the high cell
; nearest X.
DPLUS:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 4
	clc
	lda	2,X
	adc	6,X
	sta	6,X
	lda	3,X
	adc	7,X
	sta	7,X
	lda	0,X
	adc	4,X
	sta	4,X
	lda	1,X
	adc	5,X
	sta	5,X
	jmp	POPTWO

; ----------------------------------------------------------------------------
; Dictionary: MINUS [FORTH].
; Stack (from code): ( n -- -n )
; Manual: Leaves the two's complement of a number.
MINUS_NFA:
	.byte	$85,"MINU",$D3
	.word	DPLUS_NFA	; LFA: previous name field in this vocabulary chain
MINUS:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 1
	sec
negate_cell:
	tya
	sbc	0,X
	sta	0,X
	tya
	sbc	1,X
	sta	1,X
	jmp	NEXT

; ----------------------------------------------------------------------------
; Dictionary: DMINUS [FORTH].
; Stack (from code): ( d -- -d )
; Manual: Converts d1 to its double number two's complement.
DMINU_NFA:
	.byte	$86,"DMINU",$D3
	.word	MINUS_NFA	; LFA: previous name field in this vocabulary chain
; Two-cell negation: subtract the low cell from zero, then enter negate_cell with
; its borrow still in carry. The shared tail negates the high cell without
; resetting carry.
DMINU:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 2
	sec
	tya
	sbc	2,X
	sta	2,X
	tya
	sbc	3,X
	sta	3,X
	jmp	negate_cell

; ----------------------------------------------------------------------------
; Dictionary: OVER [FORTH].
; Manual stack: ( n1 n2 --- n1 n2 n1 )
; Manual: Copies the second stack value, placing it as the new top.
OVER_NFA:
	.byte	$84,"OVE",$D2
	.word	DMINU_NFA	; LFA: previous name field in this vocabulary chain
OVER:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 2
	lda	2,X
	pha
	lda	3,X
	jmp	PUSH

; ----------------------------------------------------------------------------
; Dictionary: DROP [FORTH].
; Manual stack: ( n --- )
; Manual: Drops the number from the stack.
DROP_NFA:
	.byte	$84,"DRO",$D0
	.word	OVER_NFA	; LFA: previous name field in this vocabulary chain
DROP:
	.word	POP

; ----------------------------------------------------------------------------
; Dictionary: 2DROP [FORTH].
; Manual stack: ( n1/n2 --- ) or ( d1 --- )
; Manual: Drops the top two single length elements (16-bits) from the data
; stack, or one double length (32-bits) element from the stack. Pronounced
; "two drop."
TDROP_NFA:
	.byte	$85,"2DRO",$D0
	.word	DROP_NFA	; LFA: previous name field in this vocabulary chain
TDROP:
	.word	POPTWO

; ----------------------------------------------------------------------------
; Dictionary: SWAP [FORTH].
; Manual stack: ( n1 n2 --- n2 n1 )
; Manual: Exchanges the top two values on the stack.
SWAP_NFA:
	.byte	$84,"SWA",$D0
	.word	TDROP_NFA	; LFA: previous name field in this vocabulary chain
SWAP:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 2
	lda	2,X
	pha
	lda	0,X
	sta	2,X
	lda	3,X
	ldy	1,X
	sty	3,X
	jmp	PUT

; ----------------------------------------------------------------------------
; Dictionary: DUP [FORTH].
; Manual stack: ( n --- n n )
; Manual: Duplicates the value on the stack.
DUP_NFA:
	.byte	$83,"DU",$D0
	.word	SWAP_NFA	; LFA: previous name field in this vocabulary chain
DUP:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 1
	lda	0,X
	pha
	lda	1,X
	jmp	PUSH

; ----------------------------------------------------------------------------
; Dictionary: +! [FORTH].
; Stack (from code): ( n addr -- )
; Manual: Adds n to the value at the address, a. Pronounced "plus-store."
PSTOR_NFA:
	.byte	$82,"+",$A1
	.word	DUP_NFA	; LFA: previous name field in this vocabulary chain
PSTOR:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 2
	clc
	lda	(0,X)
	adc	2,X
	sta	(0,X)
	inc	0,X
	bne	PSTOR_HIGH_BYTE
	inc	1,X
PSTOR_HIGH_BYTE:
	lda	(0,X)
	adc	3,X
	sta	(0,X)
	jmp	POPTWO

; ----------------------------------------------------------------------------
; Dictionary: TOGGLE [FORTH].
; Stack (from code): ( addr mask -- )
; Manual: Complement the contents of address a, by the bit pattern b.
TOGGL_NFA:
	.byte	$86,"TOGGL",$C5
	.word	PSTOR_NFA	; LFA: previous name field in this vocabulary chain
TOGGL:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 2
	lda	(2,X)
	eor	0,X
	sta	(2,X)
	jmp	POPTWO

; ----------------------------------------------------------------------------
; Dictionary: @ [FORTH].
; Stack (from code): ( addr -- x )
; Manual: Leaves the 16-bit contents of the address, a. Pronounced "fetch."
AT_NFA:
	.byte	$81,$C0
	.word	TOGGL_NFA	; LFA: previous name field in this vocabulary chain
AT:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 1
	lda	(0,X)
	pha
	inc	0,X
	bne	AT_HIGH_BYTE
	inc	1,X
AT_HIGH_BYTE:
	lda	(0,X)
	jmp	PUT

; ----------------------------------------------------------------------------
; Dictionary: C@ [FORTH].
; Stack (from code): ( addr -- byte )
; Manual: Leaves the 8-bit contents of memory address. On word addressing
; computers, further specification is needed regarding byte addressing.
CAT_NFA:
	.byte	$82,"C",$C0
	.word	AT_NFA	; LFA: previous name field in this vocabulary chain
CAT:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 1
	lda	(0,X)
	sta	0,X
	sty	1,X
	jmp	NEXT

; ----------------------------------------------------------------------------
; Dictionary: ! [FORTH].
; Stack (from code): ( x addr -- )
; Manual: Stores the value of n (16 bits) at address a1. Pronounced "store"
STORE_NFA:
	.byte	$81,$A1
	.word	CAT_NFA	; LFA: previous name field in this vocabulary chain
STORE:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 2
	lda	2,X
	sta	(0,X)
	inc	0,X
	bne	STORE_HIGH_BYTE
	inc	1,X
STORE_HIGH_BYTE:
	lda	3,X
	sta	(0,X)
	jmp	POPTWO

; ----------------------------------------------------------------------------
; Dictionary: C! [FORTH].
; Stack (from code): ( byte addr -- )
; Manual: Stores 8 bits at address specified. On word addressing computers,
; further specification is necessary regarding byte addressing.
CSTOR_NFA:
	.byte	$82,"C",$A1
	.word	STORE_NFA	; LFA: previous name field in this vocabulary chain
CSTOR:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 2
	lda	2,X
	sta	(0,X)
	jmp	POPTWO

; ============================================================================
; DEFINING WORDS, CONSTANTS and USER VARIABLES
; ============================================================================

; ---------------------------------------------------------------------------
; Dictionary: : [FORTH]; immediate (executes during compilation).
; Manual: Used in the form called a colon-definition : cccc ... ; Creates a
; dictionary entry defining cccc as equivalent to the following sequence of
; FORTH word definitions '...' until 108 the next ';' or 'CODE'. The
; compiling process is done by the text interpreter as long as STATE is
; non-zero. Other details are that the CONTEXT vocabulary is set to the
; CURRENT vocabulary and that words with the precedence bit set (P) are
; executed rather than being compiled. The : must be followed by a space, and
; the ; must be preceeded by a space.
COLON_NFA:
	.byte	$C1,$BA
	.word	CSTOR_NFA	; LFA: previous name field in this vocabulary chain
COLON:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	QEXEC
    .word BEGIN_DEFINITION
	.word	SCSP
	.word	CURR
	.word	AT
	.word	CONT
	.word	STORE
	.word	CREAT
	.word	RBRAC
	.word	PSCOD
; Colon runtime: save the caller IP high/low on the return stack, set IP=W+2
; (the parameter field), and execute NEXT. A colon definition is a stream of
; CFA cells, not native jsr instructions.
DOCOL:
	lda	IP+1
	pha
	lda	IP
	pha
	clc
	lda	W
	adc	#2
	sta	IP
	tya
	adc	W+1
	sta	IP+1
	jmp	NEXT

; ---------------------------------------------------------------------------
; Dictionary: ; [FORTH]; immediate (executes during compilation).
; Manual: Terminates a colon-definition and stops further compilation.
; Compiles the run-time ;S. The ; must be preceeded by a space in a
; colon-definition.
SEMICOLON_NFA:
	.byte	$C1,$BB
	.word	COLON_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	QCSP
	.word	COMP
	.word	SEMIS	; Inline CFA operand consumed by COMPILE
	.word	SMUDGE
	.word	LBRAC
    .word 	END_DEFINITION
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: CONSTANT [FORTH].
; Manual stack: ( n --- )
; Manual: A defining word used in the form: n CONSTANT cccc to create word
; cccc, with its parameter field containing n. When cccc is later executed,
; it will push the value of n to the stack.
CONST_NFA:
	.byte	$88,"CONSTAN",$D4
	.word	SEMICOLON_NFA	; LFA: previous name field in this vocabulary chain
CONST:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	CREAT
	.word	SMUDGE
	.word	COMMA
	.word	PSCOD
; Constant runtime: fetch the little-endian parameter cell at W+2 and push
; its value.
DOCON:
	ldy	#2
	lda	(W),Y
	pha
	iny
	lda	(W),Y
	jmp	PUSH

; ---------------------------------------------------------------------------
; Dictionary: VARIABLE [FORTH].
; Manual: A defining word used in the form: n VARIABLE cccc When VARIABLE is
; executed, it creates the definition cccc with its parameter field
; initialized to n. When cccc is later executed, the address of its parameter
; field (containing n) is left on the stack, so that a fetch (@) or store (!)
; may have access to this location.
VAR_NFA:
	.byte	$88,"VARIABL",$C5
	.word	CONST_NFA	; LFA: previous name field in this vocabulary chain
VAR:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	CONST
	.word	PSCOD
; Variable runtime: push W+2, the parameter-field address. For ROM-resident
; tables this address is readable data, not necessarily writable storage.
DOVAR:
	clc
	lda	W
	adc	#2
	pha
	tya
	adc	W+1
	jmp	PUSH

; ---------------------------------------------------------------------------
; Dictionary: USER [FORTH].
; Manual stack: ( n --- )
; Manual: A defining word used in the form: n USER cccc which creates a user
; variable cccc. The parameter field of cccc contains n as a fixed offset
; relative to the user pointer register UP for this user variable. When cccc
; is later executed, It places the sum of its offset and the user area base
; address on the stack as the storage address of that particular variable.
USER_NFA:
	.byte	$84,"USE",$D2
	.word	VAR_NFA	; LFA: previous name field in this vocabulary chain
USER:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	CONST
	.word	PSCOD
; User runtime: read only the byte at W+2 and add it to UP. Some later
; definitions store the offset as .word, but its high byte is still ignored.
DOUSE:
	ldy	#2
	clc
	lda	(W),Y
	adc	UP
	pha
	lda	#0
	adc	UP+1
	jmp	PUSH

; ---------------------------------------------------------------------------
; Dictionary: 0 [FORTH].
; Implementation: ( -- 0 ) Push the constant zero.
ZERO_NFA:
	.byte	$81,$B0
	.word	USER_NFA	; LFA: previous name field in this vocabulary chain
ZERO:
	.word	DOCON	; CFA: constant; push the following 16-bit value
	.word	0

; ---------------------------------------------------------------------------
; Dictionary: 1 [FORTH].
; Implementation: ( -- 1 ) Push the constant one.
ONE_NFA:
	.byte	$81,$B1
	.word	ZERO_NFA	; LFA: previous name field in this vocabulary chain
ONE:
	.word	DOCON	; CFA: constant; push the following 16-bit value
	.word	1

; ---------------------------------------------------------------------------
; Dictionary: 2 [FORTH].
; Implementation: ( -- 2 ) Push the constant two.
TWO_NFA:
	.byte	$81,$B2
	.word	ONE_NFA	; LFA: previous name field in this vocabulary chain
TWO:
	.word	DOCON	; CFA: constant; push the following 16-bit value
	.word	2

; ---------------------------------------------------------------------------
; Dictionary: 3 [FORTH].
; Implementation: ( -- 3 ) Push the constant three.
THREE_NFA:
	.byte	$81,$B3
	.word	TWO_NFA	; LFA: previous name field in this vocabulary chain
THREE:
	.word	DOCON	; CFA: constant; push the following 16-bit value
	.word	3

; ---------------------------------------------------------------------------
; Dictionary: BL [FORTH].
; Manual stack: ( --- c )
; Manual: A constant that leaves the ASCII value for "blank." 113
BL_NFA:
	.byte	$82,"B",$CC
	.word	THREE_NFA	; LFA: previous name field in this vocabulary chain
BL:
	.word	DOCON	; CFA: constant; push the following 16-bit value
	.word	32

; ---------------------------------------------------------------------------
; Dictionary: C/L [FORTH].
; Manual: Characters per line.
CSLL_NFA:
	.byte	$83,"C/",$CC
	.word	BL_NFA	; LFA: previous name field in this vocabulary chain
CSLL:
	.word	DOCON	; CFA: constant; push the following 16-bit value
	.word	64

; ---------------------------------------------------------------------------
; Dictionary: FIRST [FORTH].
; Manual stack: ( --- n )
; Manual: A constant that leaves the address of the first (lowest) block
; buffer.
FIRST_NFA:
	.byte	$85,"FIRS",$D4
	.word	CSLL_NFA	; LFA: previous name field in this vocabulary chain
FIRST:
	.word	DOCON	; CFA: constant; push the following 16-bit value
	.word	BUFONE

; ---------------------------------------------------------------------------
; Dictionary: LIMIT [FORTH].
; Manual stack: ( --- n )
; Manual: A constant leaving the address just above the highest memory
; available for a disk or cassette buffer. Usually this is the highest memory
; system.
LIMIT_NFA:
	.byte	$85,"LIMI",$D4
	.word	FIRST_NFA	; LFA: previous name field in this vocabulary chain
LIMIT:
	.word	DOCON	; CFA: constant; push the following 16-bit value
	.word	$8000

; ---------------------------------------------------------------------------
; Dictionary: B/BUF [FORTH].
; Manual stack: ( --- n1 )
; Manual: A constant which returns the number of bytes per FORTH buffer. A
; value of 1024 in this system.
BBUF_NFA:
	.byte	$85,"B/BU",$C6
	.word	LIMIT_NFA	; LFA: previous name field in this vocabulary chain
BBUF:
	.word	DOCON	; CFA: constant; push the following 16-bit value
	.word	1024

; ---------------------------------------------------------------------------
; Dictionary: B/SCR [FORTH].
; Manual stack: ( --- n1 )
; Manual: A constant which returns the number of blocks per FORTH buffer. A
; value of 1 (one) in this system.
BSCR_NFA:
	.byte	$85,"B/SC",$D2
	.word	BBUF_NFA	; LFA: previous name field in this vocabulary chain
BSCR:
	.word	DOCON	; CFA: constant; push the following 16-bit value
	.word	1

; ---------------------------------------------------------------------------
; Dictionary: +ORIGIN [FORTH].
; Manual stack: ( n --- a )
; Manual: Leaves the memory address relative to n to the origin parameter
; area. N is the minimum address unit, either byte or word. This definition
; is used to have access to or modify the boot-up parameters at the origin
; area.
PORIG_NFA:
	.byte	$87,"+ORIGI",$CE
	.word	BSCR_NFA	; LFA: previous name field in this vocabulary chain
PORIG:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	LIT,ORIG
	.word	PLUS
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: TIB [FORTH].
; Manual stack: ( --- a )
; Manual: A user variable containing the addresses of the terminal input
; buffer.
TIB_NFA:
	.byte	$83,"TI",$C2
	.word	PORIG_NFA	; LFA: previous name field in this vocabulary chain
TIB:
	.word	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.byte	$A		; User offset $000A; initial address $094A

; ---------------------------------------------------------------------------
; Dictionary: WIDTH [FORTH].
; Manual stack: ( --- a )
; Manual: In fig-FORTH, a user variable containing the maximum number of
; letters saved in the compilation of a definitions' name. It must be 1
; through 31, with a default value of 31. The name character count and its
; natural characters are saved, up to the value in WIDTH. The value may be
; changed at any time within the above limits.
WIDTH_NFA:
	.byte	$85,"WIDT",$C8
	.word	TIB_NFA	; LFA: previous name field in this vocabulary chain
WIDTH:
	.word	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.byte	$C		; User offset $000C; initial address $094C

; ---------------------------------------------------------------------------
; Dictionary: FENCE [FORTH].
; Manual stack: ( --- a )
; Manual: A user variable containing an address below which FORGETting is
; trapped. To FORGET below this point, the user must alter the contents of
; FENCE.
FENCE_NFA:
	.byte	$85,"FENC",$C5
	.word	WIDTH_NFA	; LFA: previous name field in this vocabulary chain
FENCE:
	.word	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.byte	$10	;	 User offset $0010; initial address $0950

; ---------------------------------------------------------------------------
; Dictionary: DP [FORTH].
; Manual stack: ( --- a )
; Manual: A user variable, the dictionary pointer, which contains the address
; of the next free memory above the dictionary. The value may be read by HERE
; and altered by ALLOT.
DP_NFA:
	.byte	$82,"D",$D0
	.word	FENCE_NFA	; LFA: previous name field in this vocabulary chain
DP:	.word	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.byte	$12		; User offset $0012; initial address $0952

; ---------------------------------------------------------------------------
; Dictionary: VOC-LINK [FORTH].
; Manual stack: ( --- a )
; Manual: A user variable containing the address of a field in the definition
; of most recently created vocabulary. All vocabulary names are linked by
; these fields to allow control for FORGETting through multiple vocabularies.
VOCL_NFA:
	.byte	$88,"VOC-LIN",$CB
	.word	DP_NFA	; LFA: previous name field in this vocabulary chain
VOCL:
	.word	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.byte	$14		; User offset $0014; initial address $0954

; ---------------------------------------------------------------------------
; Dictionary: BLK [FORTH].
; Manual stack: ( --- a )
; Manual: A user variable containing the block number being interpreted. If
; zero, input is being taken from the terminal input buffer.
BLK_NFA:
	.byte	$83,"BL",$CB
	.word	VOCL_NFA	; LFA: previous name field in this vocabulary chain
BLK:
	.word	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.byte	$16		; User offset $0016; initial address $0956

; ---------------------------------------------------------------------------
; Dictionary: IN [FORTH].
; Manual stack: ( --- a )
; Manual: A user variable containing the byte offset within the current input
; text buffer (terminal or disk) from which the next text will be accepted.
; WORD uses and moves the value of IN.
IN_NFA:
	.byte	$82,"I",$CE
	.word	BLK_NFA	; LFA: previous name field in this vocabulary chain
IN:
	.word	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.byte	$18		; User offset $0018; initial address $0958

; ---------------------------------------------------------------------------
; Dictionary: OUT [FORTH].
; Manual stack: ( --- a )
; Manual: A user variable that contains a value incremented by EMIT. The user
; may alter and examine OUT to control display formatting.
OUT_NFA:
	.byte	$83,"OU",$D4
	.word	IN_NFA	; LFA: previous name field in this vocabulary chain
OUT:
	.word	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.byte	$1A		; User offset $001A; initial address $095A

; ---------------------------------------------------------------------------
; Dictionary: SCR [FORTH].
; Manual stack: ( --- a )
; Manual: A user variable containing the screen number most recently
; referenced by LIST.
SCR_NFA:
	.byte	$83,"SC",$D2
	.word	OUT_NFA	; LFA: previous name field in this vocabulary chain
SCR:
	.word	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.byte	$1C		; User offset $001C; initial address $095C

; ---------------------------------------------------------------------------
; Dictionary: BMAX [FORTH].
; Manual stack: ( --- a1 )
; Manual: The FORTH user variable which specifies the highest screen that
; will be accessible with BLOCK operations. This variable is initialized to
; 16, equal to the number of screen buffers available.
BMAX_NFA:
	.byte	$84,"BMA",$D8
	.word	SCR_NFA		; LFA: previous name field in this vocabulary chain
BMAX:
	.word	DOUSE		; CFA: user variable; push UP + unsigned offset byte
	.byte	$1E			; User offset $001E; initial address $095E

; ---------------------------------------------------------------------------
; Dictionary: CONTEXT [FORTH].
; Manual stack: ( --- a )
; Manual: A user variable containing a pointer to the vocabulary within which
; dictionary searches will first begin.
CONT_NFA:
	.byte	$87,"CONTEX",$D4
	.word	BMAX_NFA		; LFA: previous name field in this vocabulary chain
CONT:	.word	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.byte	$20			; User offset $0020; initial address $0960

; ---------------------------------------------------------------------------
; Dictionary: CURRENT [FORTH].
; Manual stack: ( --- a1 )
; Manual: Leaves the address of the variable that specifies the vocabulary
; into which you are adding new word definitions.
CURR_NFA:
	.byte	$87,"CURREN",$D4
	.word	CONT_NFA		; LFA: previous name field in this vocabulary chain
CURR:
	.word	DOUSE		; CFA: user variable; push UP + unsigned offset byte
	.byte	$22			; User offset $0022; initial address $0962

; ---------------------------------------------------------------------------
; Dictionary: STATE [FORTH].
; Manual stack: ( --- a )
; Manual: A user variable containing the compilation state. A nonzero value
; indicates compilation. The value itself may be implementation dependent.
; 145
STATE_NFA:
	.byte	$85,"STAT",$C5
	.word	CURR_NFA		; LFA: previous name field in this vocabulary chain
STATE:
	.word	DOUSE		; CFA: user variable; push UP + unsigned offset byte
	.byte	$24			; User offset $0024; initial address $0964

; ---------------------------------------------------------------------------
; Dictionary: BASE [FORTH].
; Manual stack: ( --- a )
; Manual: A user variable containing the current number base used for input
; and output conversion.
BASE_NFA:
	.byte	$84,"BAS",$C5
	.word	STATE_NFA		; LFA: previous name field in this vocabulary chain
BASE:
	.word	DOUSE		; CFA: user variable; push UP + unsigned offset byte
	.byte	$26			; User offset $0026; initial address $0966

; ---------------------------------------------------------------------------
; Dictionary: DPL [FORTH].
; Manual stack: ( --- a )
; Manual: A user variable containing the number of digits to the right of the
; decimal on double integer input. It may also be used to hold output column
; location of a decimal point, in user generated formatting. The default
; value on single number input is -1.
DPL_NFA:
	.byte	$83,"DP",$CC
	.word	BASE_NFA		; LFA: previous name field in this vocabulary chain
DPL:
	.word	DOUSE		; CFA: user variable; push UP + unsigned offset byte
	.byte	$28			; User offset $0028; initial address $0968

; ---------------------------------------------------------------------------
; Dictionary: CSP [FORTH].
; Manual stack: ( --- a )
; Manual: A user variable temporarily storing the stack pointer position for
; compilation error checking.
CSP_NFA:
	.byte	$83,"CS",$D0
	.word	DPL_NFA		; LFA: previous name field in this vocabulary chain
CSP:
	.word	DOUSE		; CFA: user variable; push UP + unsigned offset byte
	.byte	$2C			; User offset $002C; initial address $096C

; ---------------------------------------------------------------------------
; Dictionary: R# [FORTH].
; Manual stack: ( --- a )
; Manual: A user variable which may contain the location of an editing
; cursor, or other file related functions.
RNUM_NFA:
	.byte	$82,"R",$A3
	.word	CSP_NFA		; LFA: previous name field in this vocabulary chain
RNUM:
	.word	DOUSE		; CFA: user variable; push UP + unsigned offset byte
	.byte	$2E			; User offset $002E; initial address $096E

; ---------------------------------------------------------------------------
; Dictionary: HLD [FORTH].
; Manual stack: ( --- a )
; Manual: A user variable that holds the address of the latest character of
; text during numeric output conversion. 130
HLD_NFA:
	.byte	$83,"HL",$C4
	.word	RNUM_NFA		; LFA: previous name field in this vocabulary chain
HLD:
	.word	DOUSE		; CFA: user variable; push UP + unsigned offset byte
	.byte	$30			; User offset $0030; initial address $0970

; ---------------------------------------------------------------------------
; Dictionary: I/O [FORTH].
; Manual stack: ( --- a1 )
; Manual: A user array, containing the CFA's of the VECTORED words in
; 64FORTH. See the section on VECTORED WORDS, for further information.
IO_NFA:
	.byte	$83,"I/",$CF
	.word	HLD_NFA		; LFA: previous name field in this vocabulary chain
IO:
	.word	DOUSE		; CFA: user variable; push UP + unsigned offset byte
	.byte	$32			; User offset $0032; initial address $0972

; ---------------------------------------------------------------------------
; Dictionary: F# [FORTH].
; Manual stack: ( --- a1 )
; Manual: A user variable, which holds the current file number for all READ
; and WRITE operations. Defaults to one (1) for CASSETTE operation.
FNUM_NFA:
	.byte	$82,"F",$A3
	.word	IO_NFA		; LFA: previous name field in this vocabulary chain
FNUM:
	.word	DOUSE		; CFA: user variable; push UP + unsigned offset byte
	.byte	$4C			; User offset $004C; initial address $098C

; ---------------------------------------------------------------------------
; Dictionary: D# [FORTH].
; Manual stack: ( --- a1 )
; Manual: A user variable, which holds the device number used for the READ
; and WRITE operators. Defaults to one (1), CASSETTE.
DNUM_NFA:
	.byte	$82,"D",$A3
	.word	FNUM_NFA		; LFA: previous name field in this vocabulary chain
DNUM:
	.word	DOUSE		; CFA: user variable; push UP + unsigned offset byte
	.byte	$4E			; User offset $004E; initial address $098E

; ---------------------------------------------------------------------------
; Dictionary: CTBL [FORTH].
; Manual stack: ( --- a1 )
; Manual: 64FORTH supports CAPTURED function keys, through the use of a
; capture table. This is a SYSTEM variable, which returns the address a1 of
; the current capture table. The table consists of a set of entries, each
; consisting of one byte, the value of the character to be captured, and a
; two byte address of the function to be performed when the character is
; entered. Here is an example entry: 0 VARIABLE TESTTABLE -2 ALLOT 3, C, ' .S
; CFA , 0 C, The table just created, contains the value 3, (CTRL C), and the
; CFA of the ".S" definition. The table is terminated with a zero byte
; following the last entry. Now whenever a CTRL C is pressed, the contents of
; the data stack will be printed out. NOTE: The key capture functions of
; 64FORTH will only work when the value in SYSTEM variable EFLAG is one (1).
; [See full entry in 64FORTH.TXT.]
CTBL_NFA:
	.byte	$84,"CTB",$CC
	.word	DNUM_NFA		; LFA: previous name field in this vocabulary chain
CTBL:
	.word	DOUSE		; CFA: user variable; push UP + unsigned offset byte
	.byte	$4A			; User offset $004A; initial address $098A

; ---------------------------------------------------------------------------
; Dictionary: EFLAG [FORTH].
; Manual stack: ( --- a1 )
; Manual: A user variable, which specifies if the edit mode is selected. If
; this variable is not zero, EXPECT obtains characters from the KERNEL one
; character at a time, and no Commodore screen editor functions are
; available. If the variable contains zero (0), characters are obtained from
; the KERNEL with the line read routine, and all Commodore screen edit
; functions are operational. This is the normal mode when the editor is not
; selected.
EFLAG_NFA:
	.byte	$85,"EFLA",$C7
	.word	CTBL_NFA		; LFA: previous name field in this vocabulary chain
EFLAG:
	.word	DOUSE		; CFA: user variable; push UP + unsigned offset byte
	.byte	$C0			; User offset $00C0; initial address $0A00

; ---------------------------------------------------------------------------
; Dictionary: DR# [FORTH].
; Manual stack: ( --- a1 )
; Manual: A user variable which holds the device number of the currently
; active disk drive. Defaults to drive 0, device 8, and may be changed with
; the word DRIVE, and checked with the word DRIVE?.
DRNUM_NFA:
	.byte	$83,"DR",$A3
	.word	EFLAG_NFA		; LFA: previous name field in this vocabulary chain
DRNUM:
	.word	DOUSE		; CFA: user variable; push UP + unsigned offset byte
	.byte	$C2			; User offset $00C2; initial address $0A02

; ---------------------------------------------------------------------------
; Dictionary: DCHAN [FORTH].
; Implementation: ( -- addr ) Address of the disk data-channel user variable;
; cold start selects channel 7.
DCHAN_NFA:
	.byte	$85,"DCHA",$CE
	.word	DRNUM_NFA		; LFA: previous name field in this vocabulary chain
DCHAN:
	.word	DOUSE		; CFA: user variable; push UP + unsigned offset byte
	.byte	$C4			; User offset $00C4; initial address $0A04

; ---------------------------------------------------------------------------
; Dictionary: CURVOICE [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- a1 )
; Manual: A user variable, which holds the number of the current voice on
; which the sound control words are working. This is used to simplify and
; reduce the stack operations that have to be done when working with the
; complex sound system in the SID chip.
CURVOC_NFA:
	.byte	$88,"CURVOIC",$C5
	.word	DCHAN_NFA		; LFA: previous name field in this vocabulary chain
CURVOC:
	.word	NO_C64		; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: IFLAG [FORTH].
; Implementation: ( -- addr ) Address of the editor insert/overwrite flag.
IFLAG_NFA:
	.byte	$85,"IFLA",$C7
	.word	CURVOC_NFA		; LFA: previous name field in this vocabulary chain
IFLAG:
	.word	DOUSE		; CFA: user variable; push UP + unsigned offset byte
	.byte	$D4			; User offset $00D4; initial address $0A14

; ---------------------------------------------------------------------------
; Dictionary: FN [FORTH].
; Manual stack: ( --- a1 )
; Manual: A user array, which holds the name of the current file. This array
; is 65 characters long.
FN_NFA:
	.byte	$82,"F",$CE
	.word	IFLAG_NFA		; LFA: previous name field in this vocabulary chain
FN:
	.word	DOUSE		; CFA: user variable; push UP + unsigned offset byte
	.byte	$7E			; User offset $007E; initial address $09BE

; ============================================================================
; HIGH-LEVEL COMPILER, PARSER and OUTER INTERPRETER
; ============================================================================

; ---------------------------------------------------------------------------
; Dictionary: 1+ [FORTH].
; Manual stack: ( n1 --- n2 )
; Manual: Increments n1 by 1.
ONEP_NFA:
	.byte	$82,"1",$AB
	.word	FN_NFA		; LFA: previous name field in this vocabulary chain
ONEP:
	.word	DOCOL		; CFA: colon definition; parameter field is a Forth thread
	.word	ONE
	.word	PLUS
	.word	SEMIS		; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: 2+ [FORTH].
; Manual stack: ( n1 --- n2 )
; Manual: Leaves n1 incremented by 2.
TWOP_NFA:
	.byte	$82,"2",$AB
	.word	ONEP_NFA		; LFA: previous name field in this vocabulary chain
TWOP:
	.word	DOCOL		; CFA: colon definition; parameter field is a Forth thread
	.word	TWO
	.word	PLUS
	.word	SEMIS		; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: HERE [FORTH].
; Manual stack: ( --- a )
; Manual: Leaves the address of the next available dictionary location.
HERE_NFA:
	.byte	$84,"HER",$C5
	.word	TWOP_NFA		; LFA: previous name field in this vocabulary chain
HERE:
	.word	DOCOL		; CFA: colon definition; parameter field is a Forth thread
	.word	DP
	.word	AT
	.word	SEMIS		; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ALLOT [FORTH].
; Manual stack: ( n --- )
; Manual: Adds the signed number to the dictionary pointer DP. May be used to
; reserve dictionary space or re-origin memory. N is with regard to computer
; address type (byte or word).
ALLOT_NFA:
	.byte	$85,"ALLO",$D4
	.word	HERE_NFA		; LFA: previous name field in this vocabulary chain
ALLOT:
    .word allot_checked

; ---------------------------------------------------------------------------
; Dictionary: , [FORTH].
; Manual stack: ( n --- )
; Manual: Stores n into the next available dictionary memory cell, advancing
; the dictionary pointer. Pronounced "comma."
COMMA_NFA:
	.byte	$81,$AC
	.word	ALLOT_NFA		; LFA: previous name field in this vocabulary chain
COMMA:
	.word	DOVEC		; CFA: vectored word; dispatch through UP+$32+offset
	.byte	20			; Vector byte offset 20 from I/O (UP+$32)

PCOMMA:
    .word comma_checked

; ---------------------------------------------------------------------------
; Dictionary: C, [FORTH].
; Manual stack: ( b --- )
; Manual: Stores 8 bits of b into the next available dictionary byte,
; advancing the dictionary pointer. This is only available on byte addressing
; computers.
CCOM_NFA:
	.byte	$82,"C",$AC
	.word	COMMA_NFA		; LFA: previous name field in this vocabulary chain
CCOM:
	.word	DOVEC		; CFA: vectored word; dispatch through UP+$32+offset
	.byte	18			; Vector byte offset 18 from I/O (UP+$32)

PCCOM:
    .word ccomma_checked

; ---------------------------------------------------------------------------
; Dictionary: - [FORTH].
; Manual stack: ( n1 n2 --- diff )
; Manual: Leaves the difference of n1 minus n2 on the stack.
SUBB_NFA:
	.byte	$81,$AD
	.word	CCOM_NFA		; LFA: previous name field in this vocabulary chain
SUBB:
	.word	DOCOL		; CFA: colon definition; parameter field is a Forth thread
	.word	MINUS
	.word	PLUS
	.word	SEMIS		; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: = [FORTH].
; Manual stack: ( n1 n2 --- f )
; Manual: Leaves a true flag if n1=n2; otherwise leaves a false flag.
EQUAL_NFA:
	.byte	$81,$BD
	.word	SUBB_NFA		; LFA: previous name field in this vocabulary chain
EQUAL:
	.word	DOCOL		; CFA: colon definition; parameter field is a Forth thread
	.word	SUBB
	.word	ZEQU
	.word	SEMIS		; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: U< [FORTH].
; Manual stack: ( u1 u2 --- <f )
; Manual: Compares the two unsigned numbers and leaves a flag representing
; the truth of the statement u1 < u2 on the stack.
ULESS_NFA:
	.byte	$82,"U",$BC
	.word	EQUAL_NFA		; LFA: previous name field in this vocabulary chain
ULESS:
	.word	*+2			; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 2
	sec
	lda	2,X
	sbc	0,X
	lda	3,X
	sbc	1,X
	inx
	inx
	bcs	ULESS_FALSE
	lda	#1
	pha
	lda	#0
	jmp	PUT

ULESS_FALSE:
	lda	#0
	pha
	jmp	PUT

; ---------------------------------------------------------------------------
; Dictionary: < [FORTH].
; Manual stack: ( n1 n2 --- f )
; Manual: Leaves a true flag if n1 is less than n2; otherwise leaves a false
; flag.
LESS_NFA:
	.byte	$81,$BC
	.word	ULESS_NFA		; LFA: previous name field in this vocabulary chain
LESS:
	.word	*+2			; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 2
	sec
	lda	2,X
	sbc	0,X
	lda	3,X
	sbc	1,X
	sty	3,X
	BVC	LESS_CHECK_SIGN
	eor	#$80
LESS_CHECK_SIGN:
	bpl	LESS_STORE_FLAG
	iny
LESS_STORE_FLAG:
	sty	2,X
	jmp	POP

; ---------------------------------------------------------------------------
; Dictionary: > [FORTH].
; Manual stack: ( n1 n2 --- f )
; Manual: Leaves a true flag if n1 is greater than n2; otherwise leaves a
; false flag.
GREAT_NFA:
	.byte	$81,$BE
	.word	LESS_NFA		; LFA: previous name field in this vocabulary chain
GREAT:
	.word	DOCOL		; CFA: colon definition; parameter field is a Forth thread
	.word	SWAP
	.word	LESS
	.word	SEMIS		; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ROT [FORTH].
; Implementation: ( a b c -- b c a ) Rotate the third cell to the top using
; the return stack temporarily.
ROT_NFA:
	.byte	$83,"RO",$D4
	.word	GREAT_NFA		; LFA: previous name field in this vocabulary chain
ROT:
	.word	DOCOL		; CFA: colon definition; parameter field is a Forth thread
	.word	TOR
	.word	SWAP
	.word	RFROM
	.word	SWAP
	.word	SEMIS		; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: SPACE [FORTH].
; Manual: Transmits an ASCII blank to the output device.
SPACE_NFA:
	.byte	$85,"SPAC",$C5
	.word	ROT_NFA		; LFA: previous name field in this vocabulary chain
SPACE:
	.word	DOCOL		; CFA: colon definition; parameter field is a Forth thread
	.word	BL
	.word	EMIT
	.word	SEMIS		; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: -DUP [FORTH].
; Manual stack: ( n1 --- n1 ) (if zero)
; Manual: ( n1 --- n1 n1 ) (non-zero) Reproduces n1 only if it is non-zero.
; Usually this is used to copy a value just before IF, to eliminate the need
; for an ELSE part to drop it.
QDUP_NFA:
	.byte	$84,"-DU",$D0
	.word	SPACE_NFA		; LFA: previous name field in this vocabulary chain
QDUP:
	.word	DOCOL		; CFA: colon definition; parameter field is a Forth thread
	.word	DUP
	.word	ZBRAN,4		; Pop flag; if zero branch to $8A95 (offset +4 from operand cell)
	.word	DUP
	.word	SEMIS		; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: TRAVERSE [FORTH].
; Manual stack: ( a1 n --- a2 )
; Manual: Moves across the name field of the fig-FORTH variable length name
; field. a1 is the address of either length byte or the last letter. If n=1,
; the motion is toward high memory; If n=-1, the motion is toward low memory.
; The a2 resulting is the address of the other end of the name. 147
TRAV_NFA:
	.byte	$88,"TRAVERS",$C5
	.word	QDUP_NFA		; LFA: previous name field in this vocabulary chain
TRAV:
	.word	DOCOL		; CFA: colon definition; parameter field is a Forth thread
	.word	SWAP
	.word	OVER
	.word	PLUS
	.word	CLIT		; Push following inline byte, zero-extended
	.byte	$7F
	.word	OVER
	.word	CAT
	.word	LESS
	.word	ZBRAN,$FFF1	; Pop flag; if zero branch to $8AA6 (offset -15 from operand cell)
	.word	SWAP
	.word	DROP
	.word	SEMIS		; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: LATEST [FORTH].
; Manual stack: ( --- a )
; Manual: Leaves the name field address of the topmost word in the CURRENT
; vocabulary.
LATES_NFA:
	.byte	$86,"LATES",$D4
	.word	TRAV_NFA		; LFA: previous name field in this vocabulary chain
LATES:
	.word	DOCOL		; CFA: colon definition; parameter field is a Forth thread
	.word	CURR
	.word	AT
	.word	AT
	.word	SEMIS		; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: LFA [FORTH].
; Manual stack: ( pfa --- lfa )
; Manual: Converts the parameter field address of a dictionary definition to
; its link address.
LFA_NFA:
	.byte	$83,"LF",$C1
	.word	LATES_NFA		; LFA: previous name field in this vocabulary chain
LFA:
	.word	DOCOL		; CFA: colon definition; parameter field is a Forth thread
	.word	CLIT		; Push following inline byte, zero-extended
	.byte	4
	.word	SUBB
	.word	SEMIS		; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: CFA [FORTH].
; Manual stack: ( pfa --- cfa )
; Manual: Converts the parameter field address of a definition to its code
; field address.
CFA_NFA:
	.byte	$83,"CF",$C1
	.word	LFA_NFA		; LFA: previous name field in this vocabulary chain
CFA:
	.word	DOCOL		; CFA: colon definition; parameter field is a Forth thread
	.word	TWO
	.word	SUBB
	.word	SEMIS		; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: NFA [FORTH].
; Manual stack: ( pfa --- nfa )
; Manual: Converts the parameter field address of a definition to its name
; field address.
NFA_NFA:
	.byte	$83,"NF",$C1
	.word	CFA_NFA		; LFA: previous name field in this vocabulary chain
NFA:
	.word	DOCOL		; CFA: colon definition; parameter field is a Forth thread
	.word	CLIT		; Push following inline byte, zero-extended
	.byte	5
	.word	SUBB
    .word   LIT,$FFFF  	; Push -1: traverse backward through the name
    .word   TRAV
    .word	SEMIS		; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: PFA [FORTH].
; Manual stack: ( nfa --- pfa )
; Manual: Converts the name field address of a compiled definition to its
; parameter field address.
PFA_NFA:
	.byte	$83,"PF",$C1
	.word	NFA_NFA		; LFA: previous name field in this vocabulary chain
PFA:
	.word	DOCOL		; CFA: colon definition; parameter field is a Forth thread
	.word	ONE
	.word	TRAV
	.word	CLIT		; Push following inline byte, zero-extended
	.byte	5
	.word	PLUS
	.word	SEMIS		; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: !CSP [FORTH].
; Manual: Saves the stack position in CSP. Used as a part of the compiler
; security.
SCSP_NFA:
	.byte	$84,"!CS",$D0
	.word	PFA_NFA		; LFA: previous name field in this vocabulary chain
SCSP:
	.word	DOCOL		; CFA: colon definition; parameter field is a Forth thread
	.word	SPAT
	.word	CSP
	.word	STORE
	.word	SEMIS		; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ?ERROR [FORTH].
; Manual stack: ( f n --- )
; Manual: Issues an error message number, if the boolean flag is true.
QERR_NFA:
	.byte	$86,"?ERRO",$D2
	.word	SCSP_NFA		; LFA: previous name field in this vocabulary chain
QERR:
	.word	DOCOL		; CFA: colon definition; parameter field is a Forth thread
	.word	SWAP
	.word	ZBRAN,4		; Pop flag; if zero branch to $8B39 (offset +4 from operand cell)
	.word	ERROR
	.word	DROP
	.word	SEMIS		; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ?COMP [FORTH].
; Manual: Issues an error message if not compiling.
QCOMP_NFA:
	.byte	$85,"?COM",$D0
	.word	QERR_NFA		; LFA: previous name field in this vocabulary chain
QCOMP:
	.word	DOCOL		; CFA: colon definition; parameter field is a Forth thread
	.word	STATE
	.word	AT
	.word	ZEQU
	.word	CLIT		; Push following inline byte, zero-extended
	.byte	$11
	.word	QERR
	.word	SEMIS		; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ?EXEC [FORTH].
; Manual: Issues an error message if not executing.
QEXEC_NFA:
	.byte	$85,"?EXE",$C3
	.word	QCOMP_NFA		; LFA: previous name field in this vocabulary chain
QEXEC:
	.word	DOCOL		; CFA: colon definition; parameter field is a Forth thread
	.word	STATE
	.word	AT
	.word	CLIT		; Push following inline byte, zero-extended
	.byte	$12
	.word	QERR
	.word	SEMIS		; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ?PAIRS [FORTH].
; Implementation: ( actual expected -- ) Compare compiler control markers and
; raise error 19 if unequal.
QPAIR_NFA:
	.byte	$86,"?PAIR",$D3
	.word	QEXEC_NFA		; LFA: previous name field in this vocabulary chain
QPAIR:
	.word	DOCOL		; CFA: colon definition; parameter field is a Forth thread
	.word	SUBB
	.word	CLIT		; Push following inline byte, zero-extended
	.byte	$13
	.word	QERR
	.word	SEMIS		; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ?CSP [FORTH].
; Manual: Issues an error message if stack position differs from value saved
; in CSP.
QCSP_NFA:
	.byte	$84,"?CS",$D0
	.word	QPAIR_NFA		; LFA: previous name field in this vocabulary chain
QCSP:
	.word	DOCOL		; CFA: colon definition; parameter field is a Forth thread
	.word	SPAT
	.word	CSP
	.word	AT
	.word	SUBB
	.word	CLIT		; Push following inline byte, zero-extended
	.byte	$14
	.word	QERR
	.word	SEMIS		; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ?LOADING [FORTH].
; Manual: Issues an error message if not loading.
QLOAD_NFA:
	.byte	$88,"?LOADIN",$C7
	.word	QCSP_NFA		; LFA: previous name field in this vocabulary chain
QLOAD:
	.word	DOCOL		; CFA: colon definition; parameter field is a Forth thread
	.word	BLK
	.word	AT
	.word	ZEQU
	.word	CLIT		; Push following inline byte, zero-extended
	.byte	$16
	.word	QERR
	.word	SEMIS		; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: COMPILE [FORTH].
; Manual stack: ( --- )
; Manual: When the word containing COMPILE executes the execution address of
; the word following COMPILE is copied (compiled) into the dictionary. This
; allows specific compilation situations to be handled in addition to simply
; compiling an execution address (which the interpreter has already done).
COMP_NFA:
	.byte	$87,"COMPIL",$C5
	.word	QLOAD_NFA		; LFA: previous name field in this vocabulary chain
COMP:
	.word	DOCOL		; CFA: colon definition; parameter field is a Forth thread
	.word	QCOMP
	.word	RFROM
	.word	DUP
	.word	TWOP
	.word	TOR
	.word	AT
	.word	COMMA
	.word	SEMIS		; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: [ [FORTH]; immediate (executes during compilation).
; Manual: Used in a colon-definition in the form: : xxx [words] more ; Leaves
; the compile mode. The words after [ are executed, not compiled. This allows
; calculation or compilation exceptions before resuming compilation with ].
; Called "leftbracket."
LBRAC_NFA:
	.byte	$C1,$DB
	.word	COMP_NFA		; LFA: previous name field in this vocabulary chain
LBRAC:
	.word	DOCOL		; CFA: colon definition; parameter field is a Forth thread
	.word	ZERO
	.word	STATE
	.word	STORE
	.word	SEMIS		; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ] [FORTH].
; Manual: Resumes compilation to the completion of a colondefinition. See [.
; Called "right bracket."
RBRAC_NFA:
	.byte	$81,$DD
	.word	LBRAC_NFA		; LFA: previous name field in this vocabulary chain
RBRAC:
	.word	DOCOL		; CFA: colon definition; parameter field is a Forth thread
	.word	CLIT		; Push following inline byte, zero-extended
	.byte	$C0
	.word	STATE
	.word	STORE
	.word	SEMIS		; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: SMUDGE [FORTH].
; Manual: Used during word definition to toggle the "smudge bit" in a
; definitions' name field. This prevents an uncompleted definition from being
; found during dictionary searches, until compiling is completed without
; error.
SMUDGE_NFA:
	.byte	$86,"SMUDG",$C5
	.word	RBRAC_NFA	; LFA: previous name field in this vocabulary chain
SMUDGE:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	LATES
	.word	CLIT	; Push following inline byte, zero-extended
	.byte	$20
	.word	TOGGL
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: HEX [FORTH].
; Manual: Sets the numeric conversion base to sixteen (hexadecimal).
HEX_NFA:
	.byte	$83,"HE",$D8
	.word	SMUDGE_NFA	; LFA: previous name field in this vocabulary chain
HEX:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	CLIT	; Push following inline byte, zero-extended
	.byte	$10
	.word	BASE
	.word	STORE
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: DECIMAL [FORTH].
; Manual: Set the numeric conversion BASE for decimal input-output.
DECIM_NFA:
	.byte	$87,"DECIMA",$CC
	.word	HEX_NFA	; LFA: previous name field in this vocabulary chain
DECIM:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	CLIT	; Push following inline byte, zero-extended
	.byte	$A
	.word	BASE
	.word	STORE
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: (;CODE) [FORTH].
; Manual: The run-time procedure, compiled by ;CODE that rewrites the code
; field of the most recently defined word to point to the following machine
; code sequence. See ;CODE.
PSCOD_NFA:
	.byte	$87,"(;CODE",$A9
	.word	DECIM_NFA	; LFA: previous name field in this vocabulary chain
PSCOD:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	RFROM
	.word	LATES
	.word	PFA
	.word	CFA
	.word	STORE
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ;CODE [FORTH]; immediate (executes during compilation).
; Manual stack: ( --- )
; Manual: Used to conclude a colon-definition in the form: : (name) ... ;CODE
; (assembly code) END-CODE. Stops compilation and terminates a new defining
; word (name). Sets the CONTEXT vocabulary to ASSEMBLER, assembling to
; machine code the following mnemonics. An existing defining word must exist
; in (name) prior to ;CODE. When (name) later executes in the form: (name)
; (namex), the definition (namex) will be created with its execution
; procedure given by the machine code following (name). That is, when (namex)
; is executed, the address interpreter jumps to the code following ;CODE in
; (name).
SEMICOLON_CODE_NFA:
	.byte	$C5,";COD",$C5
	.word	PSCOD_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	QCSP
	.word	COMP
	.word	PSCOD	; Inline CFA operand consumed by COMPILE
	.word	LBRAC
	.word	SMUDGE
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: <BUILDS [FORTH].
; Manual: Used within a colon-definition: : cccc <BUILDS DOES> ... ; Each
; time cccc is executed, <BUILDS defines a new word with a high level
; execution procedure. Executing cccc in the form: cccc nnnn uses <BUILDS to
; create a dictionary entry for nnnn. When nnnn is later executed, it has the
; address of its parameter 109 area on the stack and executes the words after
; DOES> in cccc. <BUILDS and DOES> allow run-time procedures to be written in
; high level rather than in assembler code (as required by ;CODE).
BUILD_NFA:
	.byte	$87,"<BUILD",$D3
	.word	SEMICOLON_CODE_NFA	; LFA: previous name field in this vocabulary chain
BUILD:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	ZERO
	.word	CONST
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: DOES> [FORTH].
; Manual: A word which defines the run-time action within a high level
; defining word. DOES> alters the code field and first parameter of the new
; word to execute the sequence of compiled word addresses following DOES>.
; Used in combination with <BUILDS. When the DOES> part 122 executes, it
; begins with the address of the first parameter of the new word on the
; stack. This allows interpretation using this area or its contents. Typical
; uses include the FORTH assembler, multi-dimensional arrays, and compiler
; generation.
DOES_NFA:
	.byte	$85,"DOES",$BE
	.word	BUILD_NFA	; LFA: previous name field in this vocabulary chain
DOES:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	RFROM
	.word	LATES
	.word	PFA
	.word	STORE
	.word	PSCOD
; DOES> runtime: save caller IP, load the behavior thread address from W+2,
; and push W+4 (the instance data address). Unlike DOCOL, the first parameter
; cell is a behavior pointer.
DODOE:
	lda	IP+1
	pha
	lda	IP
	pha
	ldy	#2
	lda	(W),Y
	sta	IP
	iny
	lda	(W),Y
	sta	IP+1
	clc
	lda	W
	adc	#4
	pha
	lda	W+1
	adc	#0
	jmp	PUSH

; ---------------------------------------------------------------------------
; Dictionary: COUNT [FORTH].
; Manual stack: ( a1 --- a2 n)
; Manual: Leaves the byte address a2 and byte count n of a message text
; beginning at address a1. It is presumed that the first byte at a1 contains
; the text byte count and the actual text starts with the second byte.
; Typically COUNT is followed by TYPE.
COUNT_NFA:
	.byte	$85,"COUN",$D4
	.word	DOES_NFA	; LFA: previous name field in this vocabulary chain
COUNT:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	DUP
	.word	ONEP
	.word	SWAP
	.word	CAT
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: TYPE [FORTH].
; Manual stack: ( a count --- )
; Manual: Transmits count characters from address a, to the selected output
; device.
TYPE_NFA:
	.byte	$84,"TYP",$C5
	.word	COUNT_NFA	; LFA: previous name field in this vocabulary chain
TYPE:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	QDUP
	.word	ZBRAN,$1D	; Pop flag; if zero branch to $8CD2 (offset +29 from operand cell)
	.word	OVER
	.word	PLUS
	.word	SWAP
	.word	PDO
	.word	I
	.word	CAT
	.word	CLIT	; Push following inline byte, zero-extended
	.byte	$7F
	.word	ANDD
	.word	EMIT
	.word	PLOOP,$FFF3	; Increment loop index; if continuing branch to $8CBF (offset -13 from operand cell)
	.word	BRAN,4	; Jump to $8CD4 (offset +4 from operand cell)
	.word	DROP
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: -TRAILING [FORTH].
; Manual stack: ( a n1 --- a n2 )
; Manual: Suppresses the output of trailing blanks, from a text string that
; starts at address a, by adjusting the character count n1. i.e., the
; characters at +n1 to a +n2 are blanks.
DTRAI_NFA:
	.byte	$89,"-TRAILIN",$C7
	.word	TYPE_NFA	; LFA: previous name field in this vocabulary chain
DTRAI:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	DUP
	.word	ZERO
	.word	PDO
	.word	TDUP
	.word	PLUS
	.word	ONE
	.word	SUBB
	.word	CAT
	.word	BL
	.word	SUBB
	.word	ZBRAN,8	; Pop flag; if zero branch to $8D02 (offset +8 from operand cell)
	.word	LEAVE
	.word	BRAN,6	; Jump to $8D06 (offset +6 from operand cell)
	.word	ONE
	.word	SUBB
	.word	PLOOP,$FFE2	; Increment loop index; if continuing branch to $8CEA (offset -30 from operand cell)
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: (.") [FORTH].
; Stack (from code): ( -- ) Consume the inline counted string.
; Manual: The run-time procedure, compiled by ." which transmits the
; following on-line text to the screen or other output device. See ."
PDOTQ_NFA:
	.byte	$84,"(.\"",$A9
	.word	DTRAI_NFA	; LFA: previous name field in this vocabulary chain
; Runtime of dot-quote: the return IP addresses a count byte and inline text.
; COUNT/TYPE print it; the saved return IP is advanced past the text so those
; bytes are not executed as CFAs.
PDOTQ:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	R
	.word	COUNT
	.word	DUP
	.word	ONEP
	.word	RFROM
	.word	PLUS
	.word	TOR
	.word	TYPE
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ." [FORTH]; immediate (executes during compilation).
; Manual: Used in the form: ." cccc" Compiles an in-line string cccc
; (delimited by the trailing quotation mark) with an execution procedure to
; send the text to the selected output device. If executed outside a
; definition, ." will immediately print the text until the closing ". The
; maximum number of characters is 64. See (.") Pronounced "dot quote."
DOTQ_NFA:
	.byte	$C2,".",$A2
	.word	PDOTQ_NFA	; LFA: previous name field in this vocabulary chain
DOTQ:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	CLIT	; Push following inline byte, zero-extended
	.byte	"\""
	.word	STATE
	.word	AT
	.word	ZBRAN,$14	; Pop flag; if zero branch to $8D4B (offset +20 from operand cell)
	.word	COMP
	.word	PDOTQ	; Inline CFA operand consumed by COMPILE
	.word	WORD
	.word	HERE
	.word	CAT
	.word	ONEP
	.word	ALLOT
	.word	BRAN,$A	; Jump to $8D53 (offset +10 from operand cell)
	.word	WORD
	.word	HERE
	.word	COUNT
	.word	TYPE
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: EXPECT [FORTH].
; Manual stack: ( a1/n1 --- )
; Manual: Same as fig-FORTH, but uses the Commodore line read routine, which
; can only be terminated by a carriage return at the end of the line. If a
; fig standard version of EXPECT is required, this can be obtained by setting
; EFLAG to value of 1 (one) which causes alternate section of EXPECT code to
; be used.
EXPECT_NFA:
	.byte	$86,"EXPEC",$D4
	.word	DOTQ_NFA	; LFA: previous name field in this vocabulary chain
EXPECT:
    .word expect_serial

; ---------------------------------------------------------------------------
; Dictionary: QUERY [FORTH].
; Manual: Inputs 80 characters of text ( or until a "return") from the
; operators terminal. Text is positioned at the address contained in TIB with
; IN set to zero.
QUERY_NFA:
	.byte	$85,"QUER",$D9
	.word	EXPECT_NFA	; LFA: previous name field in this vocabulary chain
QUERY:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	TIB
	.word	AT
	.word	CLIT	; Push following inline byte, zero-extended
	.byte	127
	.word	EXPECT
	.word	ZERO
	.word	IN
	.word	STORE
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: NULL [FORTH]; immediate (executes during compilation).
; Implementation: End-of-input handler for the NUL token. Advance block input
; when loading; otherwise leave the interpreter through its return stack.
NULL_NFA:
	.byte	$C1,$80
	.word	QUERY_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	BLK
	.word	AT
	.word	ZBRAN,4	; Pop flag; if zero branch to $8E18 (offset +4 from operand cell)
	.word	QEXEC
	.word	RFROM
	.word	DROP
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: FILL [FORTH].
; Manual stack: ( a quan b --- )
; Manual: Fills memory at the address with the specified quantity of bytes b.
FILL_NFA:
	.byte	$84,"FIL",$CC
	.word	NULL_NFA	; LFA: previous name field in this vocabulary chain
FILL:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	SWAP
	.word	TOR
	.word	OVER
	.word	CSTOR
	.word	DUP
	.word	ONEP
	.word	RFROM
	.word	ONE
	.word	SUBB
	.word	CMOVE
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ERASE [FORTH].
; Manual stack: ( a n --- )
; Manual: Clears a region of memory to zero from address 'a' over 'n'
; addresses.
ERASE_NFA:
	.byte	$85,"ERAS",$C5
	.word	FILL_NFA	; LFA: previous name field in this vocabulary chain
ERASE:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	ZERO
	.word	FILL
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: BLANKS [FORTH].
; Manual stack: ( a count --- )
; Manual: Fills an area of memory beginning at address a with blanks.
BLANK_NFA:
	.byte	$86,"BLANK",$D3
	.word	ERASE_NFA	; LFA: previous name field in this vocabulary chain
BLANK:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	BL
	.word	FILL
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: HOLD [FORTH].
; Manual stack: ( c --- )
; Manual: Used between <# and #> to insert an ASCII character into a pictured
; numeric output string. e.g. 2E HOLD will place a decimal point.
HOLD_NFA:
	.byte	$84,"HOL",$C4
	.word	BLANK_NFA	; LFA: previous name field in this vocabulary chain
HOLD:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	LIT,$FFFF
	.word	HLD
	.word	PSTOR
	.word	HLD
	.word	AT
	.word	CSTOR
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: PAD [FORTH].
; Manual stack: ( --- a )
; Manual: Leaves the address of the text output buffer, which is a fixed
; offset above HERE. 137
PAD_NFA:
	.byte	$83,"PA",$C4
	.word	HOLD_NFA	; LFA: previous name field in this vocabulary chain
PAD:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	HERE
	.word	CLIT	; Push following inline byte, zero-extended
	.byte	68
	.word	PLUS
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: WORD [FORTH].
; Manual stack: ( c --- )
; Manual: Reads the next text characters from the input stream being
; interpreted until a delimiter c is found; storing the packed character
; string beginning at the dictionary buffer HERE. WORD leaves the character
; count in the first byte, the characters, and ends with two or more blanks.
; The leading occurence of c is ignored. If BLK is zero, text is taken from
; the terminal input buffer, otherwise from the block stored in BLK. See BLK,
; IN.
WORD_NFA:
	.byte	$84,"WOR",$C4
	.word	PAD_NFA	; LFA: previous name field in this vocabulary chain
WORD:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	BLK
	.word	AT
	.word	ZBRAN,$C	; Pop flag; if zero branch to $8EA3 (offset +12 from operand cell)
	.word	BLK
	.word	AT
	.word	BLOCK
	.word	BRAN,6	; Jump to $8EA7 (offset +6 from operand cell)
	.word	TIB
	.word	AT
	.word	IN
	.word	AT
	.word	PLUS
	.word	SWAP
	.word	ENCL
	.word	HERE
	.word	CLIT	; Push following inline byte, zero-extended
	.byte	"\""
	.word	BLANK
	.word	IN
	.word	PSTOR
	.word	OVER
	.word	SUBB
	.word	TOR
	.word	R
	.word	HERE
	.word	CSTOR
	.word	PLUS
	.word	HERE
	.word	ONEP
	.word	RFROM
	.word	CMOVE
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: (NUMBER) [FORTH].
; Manual stack: (d1 a1 --- d2 a2 )
; Manual: Converts the ASCII text beginning at a1+1 using the current numeric
; BASE. The new value is accumulated into double number d1, being left as d2.
; a2 is the address of the first unconvertible digit. Used by NUMBER.
PNUMB_NFA:
	.byte	$88,"(NUMBER",$A9
	.word	WORD_NFA	; LFA: previous name field in this vocabulary chain
PNUMB:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	ONEP
	.word	DUP
	.word	TOR
	.word	CAT
	.word	BASE
	.word	AT
	.word	DIGIT
	.word	ZBRAN,$2C	; Pop flag; if zero branch to $8F1D (offset +44 from operand cell)
	.word	SWAP
	.word	BASE
	.word	AT
	.word	USTAR
	.word	DROP
	.word	ROT
	.word	BASE
	.word	AT
	.word	USTAR
	.word	DPLUS
	.word	DPL
	.word	AT
	.word	ONEP
	.word	ZBRAN,8	; Pop flag; if zero branch to $8F17 (offset +8 from operand cell)
	.word	ONE
	.word	DPL
	.word	PSTOR
	.word	RFROM
	.word	BRAN,$FFC6	; Jump to $8EE1 (offset -58 from operand cell)
	.word	RFROM
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: NUMBER [FORTH].
; Manual stack: ( a --- d )
; Manual: Converts a character string left at address a with a preceeding
; count to a signed double number using the current numeric base. If a
; decimal point is encountered in the text, its position will be given in
; DPL, but no other effect occurs. If numeric conversion is not possible, an
; error message will be given. This is a vectored word.
NUMBER_NFA:
	.byte	$86,"NUMBE",$D2
	.word	PNUMB_NFA	; LFA: previous name field in this vocabulary chain
NUMBER:
	.word	DOVEC	; CFA: vectored word; dispatch through UP+$32+offset
	.byte	10	; Vector byte offset 10 from I/O (UP+$32)

PNUMBE:
	.word	DOCOL
	.word	ZERO
	.word	ZERO
	.word	ROT
	.word	DUP
	.word	ONEP
	.word	CAT
	.word	CLIT	; Push following inline byte, zero-extended
	.byte	"-"
	.word	EQUAL
	.word	DUP
	.word	TOR
	.word	PLUS
	.word	LIT,$FFFF
	.word	DPL
	.word	STORE
	.word	PNUMB
	.word	DUP
	.word	CAT
	.word	BL
	.word	SUBB
	.word	ZBRAN,$15	; Pop flag; if zero branch to $8F6F (offset +21 from operand cell)
	.word	DUP
	.word	CAT
	.word	CLIT	; Push following inline byte, zero-extended
	.byte	"."
	.word	SUBB
	.word	ZERO
	.word	QERR
	.word	ZERO
	.word	BRAN,$FFDD	; Jump to $8F4A (offset -35 from operand cell)
	.word	DROP
	.word	RFROM
	.word	ZBRAN,4	; Pop flag; if zero branch to $8F79 (offset +4 from operand cell)
	.word	DMINU
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: -FIND [FORTH].
; Manual stack: ( --- pfa b tf ) (found)
; Manual: ( --- ff ) (not found) Accepts the next text word (delimited by
; blanks) in the input stream to HERE, and searches the CONTEXT and then the
; CURRENT vocabularies for a matching entry. If found, the dictionary entry's
; parameter field address, its length in bytes, and a boolean true is left.
; Otherwise, only a boolean false is left. This is a vectored word.
DFIND_NFA:
	.byte	$85,"-FIN",$C4
	.word	NUMBER_NFA	; LFA: previous name field in this vocabulary chain
DFIND:
	.word	DOVEC	; CFA: vectored word; dispatch through UP+$32+offset
	.byte	16	; Vector byte offset 16 from I/O (UP+$32)

PDFIND:
	.word	DOCOL
	.word	BL
	.word	WORD
	.word	UPPER_TOKEN
	.word	HERE
	.word	CONT
	.word	AT
	.word	AT
	.word	PFIND
	.word	DUP
	.word	ZEQU
	.word	ZBRAN,$A	; Pop flag; if zero branch to $8FA6 (offset +10 from operand cell)
	.word	DROP
	.word	HERE
	.word	LATES
	.word	PFIND
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ERROR [FORTH].
; Manual stack: ( line --- in blk )
; Manual: Executes error notification and re-start of system. WARNING is
; first examined. If 1, the text of line n, relative to screen 4 of drive 0
; is printed. This line number may be positive or negative, and beyond just
; screen 4. If WARNING is 0, n is just printed as a message number (non disk
; installation). If WARNING is -1, the definition (ABORT) is executed which
; executes the system ABORT. 64FORTH saves the contents of IN and BLK to
; assist in determining the location of the error. Final action is execution
; of QUIT. This is a vectored word.
ERROR_NFA:
	.byte	$85,"ERRO",$D2
	.word	DFIND_NFA	; LFA: previous name field in this vocabulary chain
ERROR:
	.word	DOVEC	; CFA: vectored word; dispatch through UP+$32+offset
	.byte	12	; Vector byte offset 12 from I/O (UP+$32)

PERROR:
    .word *+2
    lda 0,x
    jmp shell_error

; ---------------------------------------------------------------------------
;	ERROR MESSAGES
; ---------------------------------------------------------------------------
; Error-number table: cells point at counted error strings below. MESSAGE
; selects one by index; these .word values are addresses, not executable
; threads.
ERROR_TABLE:
	.word	ERR_WHAT
	.word	ERR_STACK_EMPTY
	.word	ERR_OUT_OF_MEMORY
	.word	ERR_BAD_ADDR_MODE
	.word	ERR_UNKNOWN
	.word	ERR_UNKNOWN
	.word	ERR_UNKNOWN
	.word	ERR_UNKNOWN
	.word	ERR_BLOCK_RANGE
	.word	ERR_UNKNOWN
	.word	ERR_UNKNOWN
	.word	ERR_UNKNOWN
	.word	ERR_UNKNOWN
	.word	ERR_UNKNOWN
	.word	ERR_UNKNOWN
	.word	ERR_UNKNOWN
	.word	ERR_UNKNOWN
	.word	ERR_COMPILE_ONLY
	.word	ERR_EXECUTE_ONLY
	.word	ERR_CONDITIONALS
	.word	ERR_INCOMPLETE_DEFINITION
	.word	ERR_PROTECTED_WORD
	.word	ERR_LOADING_ONLY
	.word	ERR_UNKNOWN
	.word	ERR_SPECIFY_VOCABULARY
	.word	ERR_UNKNOWN
ERR_NO_C64_SLOT:
    .word   ERR_NO_C64
    .word ERR_STACK_FULL, ERR_RX_FULL, ERR_RETURN_FULL, ERR_BREAK, ERR_DIV_ZERO, ERR_LINE_LONG
ERROR_TABLE_END:

ERR_WHAT:
	.byte	4
	.byte	"WHAT"
ERR_STACK_EMPTY:
	.byte	12
	.byte	"STACK EMPTY!"
ERR_OUT_OF_MEMORY:
	.byte	13
	.byte	"OUT OF MEMORY"
ERR_UNKNOWN:
	.byte	13
	.byte	"UNKNOWN ERROR"
ERR_BAD_ADDR_MODE:
	.byte	17
	.byte	"HAS BAD ADDR MODE"
ERR_BLOCK_RANGE:
	.byte	17
	.byte	"BLOCK RANGE ERROR"
ERR_COMPILE_ONLY:
	.byte	18
	.byte	"FOR COMPILING ONLY"
ERR_EXECUTE_ONLY:
	.byte	18
	.byte	"FOR EXECUTING ONLY"
ERR_CONDITIONALS:
	.byte	21
	.byte	"IMPROPER CONDITIONALS"
ERR_INCOMPLETE_DEFINITION:
	.byte	21
	.byte	"INCOMPLETE DEFINITION"
ERR_PROTECTED_WORD:
	.byte	19
	.byte	"THIS WORD PROTECTED"
ERR_LOADING_ONLY:
	.byte	21
	.byte	"USE ONLY WHEN LOADING"
ERR_SPECIFY_VOCABULARY:
	.byte	22
	.byte	"SPECIFY THE VOCABULARY"
ERR_NO_C64:
    .byte   6
    .byte   "NO C64"

ERR_STACK_FULL:
    .byte 10,"STACK FULL"
ERR_RX_FULL:
    .byte 17,"SERIAL INPUT FULL"
ERR_RETURN_FULL:
    .byte 17,"RETURN STACK FULL"
ERR_BREAK:
    .byte 5,"BREAK"
ERR_DIV_ZERO:
    .byte 16,"DIVISION BY ZERO"
ERR_LINE_LONG:
    .byte 14,"INPUT TOO LONG"

; ---------------------------------------------------------------------------
; Dictionary: ID. [FORTH].
; Manual stack: ( a --- )
; Manual: Print a definition's name from its name field address.
IDDOT_NFA:
	.byte	$83,"ID",$AE
	.word	ERROR_NFA	; LFA: previous name field in this vocabulary chain
IDDOT:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	COUNT
	.word	CLIT	; Push following inline byte, zero-extended
	.byte	$1F
	.word	ANDD
	.word	TYPE
	.word	SPACE
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: CREATE [FORTH].
; Manual: A defining word used in the form: CREATE cccc by such words as CODE
; and CONSTANT to create a dictionary header for a FORTH definition. The code
; field contains the address of the word's parameter field. The new word is
; created in the CURRENT vocabulary. This is a vectored word.
CREAT_NFA:
	.byte	$86,"CREAT",$C5
	.word	IDDOT_NFA	; LFA: previous name field in this vocabulary chain
CREAT:
	.word	DOVEC	; CFA: vectored word; dispatch through UP+$32+offset
	.byte	8	; Vector byte offset 8 from I/O (UP+$32)

; Construct a RAM dictionary header at HERE: copy the parsed name, enforce
; WIDTH, mark name end and header flag bits, link to LATEST, and allocate the
; initial code/parameter fields. SMUDGE hides a definition while it is being
; built.
PCREAT:
	.word	DOCOL
	.word	DFIND
	.word	ZBRAN,$14	; Pop flag; if zero branch to $9126 (offset +20 from operand cell)
	.word	DROP
	.word	CR
	.word	PDOTQ	; Print counted inline text; resume after its payload
	.byte	7
	.byte	"REDEF: "
	.word	NFA
	.word	IDDOT
	.word	HERE
	.word	DUP
	.word	CAT
	.word	WIDTH
	.word	AT
	.word	MIN
	.word	ONEP
	.word	ALLOT
	.word	DUP
	.word	CLIT	; Push following inline byte, zero-extended
	.byte	$A0
	.word	TOGGL
	.word	HERE
	.word	ONE
	.word	SUBB
	.word	CLIT	; Push following inline byte, zero-extended
	.byte	$80
	.word	TOGGL
	.word	LATES
	.word	COMMA
	.word	CURR
	.word	AT
	.word	STORE
	.word	HERE
	.word	TWOP
	.word	COMMA
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: [COMPILE] [FORTH]; immediate (executes during compilation).
; Manual: Used in a colon-definition In the form: : xxx [COMPILE] FORTH ;
; [COMPILE] will force the compilation of an Immediate definition that would
; otherwise execute during compilation. The above example will select the
; FORTH vocabulary when xxx executes, rather than at compile time.
BRACKET_COMPILE_NFA:
	.byte	$C9,"[COMPILE",$DD
	.word	CREAT_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	DFIND
	.word	ZEQU
	.word	ZERO
	.word	QERR
	.word	DROP
	.word	CFA
	.word	COMMA
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: LITERAL [FORTH]; immediate (executes during compilation).
; Manual stack: ( n --- ) (compiling)
; Manual: At compile-time, the LITERAL compiles the stack value n as a 16-bit
; literal. This definition is immediate so that it will execute during a
; colon-definition. The intended use is: xxx (calculate) LITERAL 133
; Compilation is suspended for the compile time calculation of a value.
; Compilation is resumed and LITERAL compiles this value. At run-time, the
; value will be pushed onto the stack.
LITER_NFA:
	.byte	$C7,"LITERA",$CC
	.word	BRACKET_COMPILE_NFA	; LFA: previous name field in this vocabulary chain
LITER:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	STATE
	.word	AT
	.word	ZBRAN,8	; Pop flag; if zero branch to $9192 (offset +8 from operand cell)
	.word	COMP
	.word	LIT,COMMA	; First CFA is consumed by COMPILE; remaining cells resume the thread
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: DLITERAL [FORTH]; immediate (executes during compilation).
; Manual stack: ( d --- d ) (executing)
; Manual: ( d --- d ) (compiling) If compiling, compiles a stack double
; number into a literal. Later execution of this definition containing the
; literal will push it to the stack. If executing, the number remains on the
; stack.
DLIT_NFA:
	.byte	$C8,"DLITERA",$CC
	.word	LITER_NFA	; LFA: previous name field in this vocabulary chain
DLIT:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	STATE
	.word	AT
	.word	ZBRAN,8	; Pop flag; if zero branch to $91AF (offset +8 from operand cell)
	.word	SWAP
	.word	LITER
	.word	LITER
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ?STACK [FORTH].
; Manual: Issues an error message if the stack is out of bounds.
QSTAC_NFA:
	.byte	$86,"?STAC",$CB
	.word	DLIT_NFA	; LFA: previous name field in this vocabulary chain
QSTAC:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	SPAT
	.word	CLIT	; Push following inline byte, zero-extended
	.byte	TOS
	.word	SWAP
	.word	ULESS
	.word	ONE
	.word	QERR
	.word	EM
	.word	AT
	.word	HERE
	.word	CLIT	; Push following inline byte, zero-extended
	.byte	$A0
	.word	PLUS
	.word	ULESS
	.word	TWO
	.word	QERR
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: INTERPRET [FORTH].
; Manual: The outer text interpreter which sequentially executes or compiles
; text from the input stream (terminal or disk) depending on STATE. If the
; word name cannot be found after a search of CONTEXT and then CURRENT, it is
; converted to a number according to the current base. That also failing, an
; error message echoing the name with a "?" will be given. Text input will be
; taken according to the convention for the word. If a decimal point is found
; as a part of a number, a double number value will be left. The decimal
; point has no other purpose than to force this action. See NUMBER.
INTER_NFA:
	.byte	$89,"INTERPRE",$D4
	.word	QSTAC_NFA	; LFA: previous name field in this vocabulary chain
; OUTER INTERPRETER. Parse/search with -FIND. A found word is compiled or
; executed according to STATE and header immediacy. Otherwise NUMBER converts
; it; DPL distinguishes single/double literals. ?STACK validates the
; resulting data-stack position before continuing.
INTER:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	DFIND
	.word	ZBRAN,$1E	; Pop flag; if zero branch to $920C (offset +30 from operand cell)
	.word	STATE
	.word	AT
	.word	LESS
	.word	ZBRAN,$A	; Pop flag; if zero branch to $9202 (offset +10 from operand cell)
	.word	CFA
	.word	COMMA
	.word	BRAN,6	; Jump to $9206 (offset +6 from operand cell)
	.word	CFA
	.word	EXEC
	.word	QSTAC
	.word	BRAN,$1C	; Jump to $9226 (offset +28 from operand cell)
	.word	HERE
	.word	NUMBER
	.word	DPL
	.word	AT
	.word	ONEP
	.word	ZBRAN,8	; Pop flag; if zero branch to $9220 (offset +8 from operand cell)
	.word	DLIT
	.word	BRAN,6	; Jump to $9224 (offset +6 from operand cell)
	.word	DROP
	.word	LITER
	.word	QSTAC
	.word	BRAN,$FFC2	; Jump to $91EA (offset -62 from operand cell)

; ---------------------------------------------------------------------------
; Dictionary: IMMEDIATE [FORTH].
; Manual: Marks the most recently made definition so that when encountered at
; compile time, it will be executed rather than being complied, that is, the
; precedence bit in its 131 header is set. This method allows definitions to
; handle unusual compiling situations, rather than build them into the
; fundamental compiler. The user may force compilation of an IMMEDIATE
; definition by preceeding it with [COMPILE].
IMMEDIATE_NFA:
	.byte	$89,"IMMEDIAT",$C5
	.word	INTER_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	LATES
	.word	CLIT	; Push following inline byte, zero-extended
	.byte	$40
	.word	TOGGL
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: VOCABULARY [FORTH].
; Manual: A defining word used in the form: VOCABULARY cccc to create a
; vocabulary definition cccc. Subsequent use of cccc will make it the CONTEXT
; vocabulary which is searched first by INTERPRET. The sequence "cccc
; DEFINITIONS" will also make cccc the CURRENT vocabulary into which new
; definitions are placed. In fig-FORTH cccc will be chained to include all
; definitions of the vocabulary in which cccc is itself defined. All
; vocabularies ultimately chain to FORTH. By convention, vocabulary names are
; to be declared IMMEDIATE. See VOC-LINK. 150
VOCABULARY_NFA:
	.byte	$8A,"VOCABULAR",$D9
	.word	IMMEDIATE_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	BUILD
	.word	LIT,$A081
	.word	COMMA
	.word	CURR
	.word	AT
	.word	CFA
	.word	COMMA
	.word	HERE
	.word	VOCL
	.word	AT
	.word	COMMA
	.word	VOCL
	.word	STORE
	.word	DOES
DOVOC:
	.word	TWOP
	.word	CONT
	.word	STORE
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: DEFINITIONS [FORTH].
; Manual stack: ( --- )
; Manual: Used in the form: cccc DEFINITIONS Sets the current vocabulary to
; the CONTEXT vocabulary. In the example, executing vocabulary name cccc made
; it the CONTEXT vocabulary and executing DEFINITIONS made both specify
; vocabulary cccc.
DEFIN_NFA:
	.byte	$8B,"DEFINITION",$D3
	.word	VOCABULARY_NFA	; LFA: previous name field in this vocabulary chain
DEFIN:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	CONT
	.word	AT
	.word	CURR
	.word	STORE
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ( [FORTH]; immediate (executes during compilation).
; Manual: Used in the form: ( cccc ) Encloses explanatory comments which will
; be ignored by the computer. Delimited by a right parenthesis on the 102
; same line. May occur during execution or in a colondefinition. A blank
; after the leading parenthesis is required. Pronounced 1eft paren."
COMMENT_NFA:
	.byte	$C1,$A8
	.word	DEFIN_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	CLIT	; Push following inline byte, zero-extended
	.byte	")"
	.word	WORD
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: QUIT [FORTH].
; Manual: Clears the return stack. Stops compilation, and returns control to
; the operator's terminal. No message is given.
QUIT_NFA:
	.byte	$84,"QUI",$D4
	.word	COMMENT_NFA	; LFA: previous name field in this vocabulary chain
QUIT:
    .word DOCOL
    .word ZERO,BLK,STORE,LBRAC
quit_line:
    .word RPSTO
    .word STATE,AT,ZBRAN
quit_prompt_branch:
    .word quit_prompt-quit_prompt_branch
    .word PDOTQ
    .byte 4,"... "
    .word BRAN
quit_input_branch:
    .word quit_input-quit_input_branch
quit_prompt:
    .word PDOTQ
    .byte 4,"ok> "
quit_input:
    .word QUERY,INTER
    .word STATE,AT,ZBRAN
quit_done_branch:
    .word quit_done-quit_done_branch
    .word BRAN
quit_compile_branch:
    .word .loword(quit_line-quit_compile_branch)
quit_done:
    .word CR,BRAN
quit_again_branch:
    .word .loword(quit_line-quit_again_branch)

; ---------------------------------------------------------------------------
; Dictionary: ABORT [FORTH].
; IMNOTWOPR: implemented by the serial shell.
; Original C64 manual: Clears the stacks and enters the execution state. Returns control
; to the operator's terminal, printing a message appropriate to the
; Installation. 111
ABORT_NFA:
	.byte	$85,"ABOR",$D4
	.word	QUIT_NFA	; LFA: previous name field in this vocabulary chain
ABORT:
    .word shell_abort

; Native cold-thread entry: point IP directly at COLD1 (the parameter
; thread), bypassing the COLD CFA.
COLD_THREAD_ENTRY:
	lda	#>COLD1
	sta	IP+1
	lda	#<COLD1
	jmp	RESTART_THREAD

; Native warm-thread entry: point IP at WARM. Both starts clear decimal mode
; and reset the hardware/data stack pointers before NEXT.
WARM_THREAD_ENTRY:
	lda	#>WARM
	sta	IP+1
	lda	#<WARM
; Common restart: install IP low byte and reset native/Forth stack state.
RESTART_THREAD:
	sta	IP
	CLD
	ldx	#$FF
	txs
	ldx	#TOS
	jmp	NEXT

; ROM checksum descriptor. Sum bytes in [CARTRIDGE_HEADER,ROM_CHECKSUM_START) modulo 65536 and
; compare to $83E4. The descriptor and later ROM code are not in this range.
; Preserve these bytes when adding annotations.
ROM_CHECKSUM_START:
	.word	CARTRIDGE_HEADER		; CHECKSUM START ADDR
ROM_CHECKSUM_END:
	.word	ROM_CHECKSUM_START		; CHECKSUM END ADDR + 1
ROM_CHECKSUM_VALUE:
	.word	$83E4		; CHECKSUM

; ---------------------------------------------------------------------------
; Dictionary: COLD [FORTH].
; IMNOTWOPR: implemented by the serial shell.
; Original C64 manual stack: ( --- )
; Manual: The COLD start procedure adjusts the dictionary pointer to the
; minimum standard and restarts via ABORT. May be called from the terminal to
; remove application programs and restart. See EMPTY.
COLD_NFA:
	.byte	$84,"COL",$C4
	.word	ABORT_NFA	; LFA: previous name field in this vocabulary chain
COLD:
    .word shell_cold

COLD1:
    .word COLD
WARM:
    .word ABORT

; ---------------------------------------------------------------------------
; Dictionary: EMPTY [FORTH].
; Manual stack: ( --- )
; Manual: Cleans out the dictionary to the COLD condition. Similar to FORGET,
; but forgets ALL user added words.
EMPTY_NFA:
	.byte	$85,"EMPT",$D9
	.word	COLD_NFA	; LFA: previous name field in this vocabulary chain
; Restore the 78-byte vocabulary template at FORTH_NFA into RAM at $0840 and set
; DP=$1000. Execute the RAM FORTH vocabulary and DEFINITIONS to restore both
; search and compilation vocabularies, then return.
EMPTY:
    .word shell_empty

; ===========================================================================
; SIGNED ARITHMETIC, CONTROL COMPILATION and NUMBER FORMATTING
; ===========================================================================

; ---------------------------------------------------------------------------
; Dictionary: S->D [FORTH].
; Manual stack: ( n --- d )
; Manual: Sign extend a single number to form a double number.
STOD_NFA:
	.byte	$84,"S->",$C4
	.word	EMPTY_NFA	; LFA: previous name field in this vocabulary chain
STOD:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	DUP
	.word	ZLESS
	.word	MINUS
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: +- [FORTH].
; Manual stack: ( n1 n2 --- n3 )
; Manual: Applies the sign of n2 to n1, which is left as n3.
PM_NFA:
	.byte	$82,"+",$AD
	.word	STOD_NFA	; LFA: previous name field in this vocabulary chain
PM:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	ZLESS
	.word	ZBRAN,4	; Pop flag; if zero branch to $9497 (offset +4 from operand cell)
	.word	MINUS
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: D+- [FORTH].
; Manual stack: ( d1 n --- d2 )
; Manual: Applies the sign of n to the double number d1, leaving it as d2.
DPM_NFA:
	.byte	$83,"D+",$AD
	.word	PM_NFA	; LFA: previous name field in this vocabulary chain
DPM:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	ZLESS
	.word	ZBRAN,4	; Pop flag; if zero branch to $94A9 (offset +4 from operand cell)
	.word	DMINU
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ABS [FORTH].
; Manual stack: ( n --- u )
; Manual: Leaves the absolute value of n as u.
ABS_NFA:
	.byte	$83,"AB",$D3
	.word	DPM_NFA	; LFA: previous name field in this vocabulary chain
ABS:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	DUP
	.word	PM
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: DABS [FORTH].
; Manual stack: ( d --- ud )
; Manual: Leaves the absolute value ud of a double number.
DABS_NFA:
	.byte	$84,"DAB",$D3
	.word	ABS_NFA	; LFA: previous name field in this vocabulary chain
DABS:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	DUP
	.word	DPM
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: MIN [FORTH].
; Manual stack: ( n1 n2 --- min )
; Manual: Leaves the smaller of two numbers.
MIN_NFA:
	.byte	$83,"MI",$CE
	.word	DABS_NFA	; LFA: previous name field in this vocabulary chain
MIN:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	TDUP
	.word	GREAT
	.word	ZBRAN,4	; Pop flag; if zero branch to $94DA (offset +4 from operand cell)
	.word	SWAP
	.word	DROP
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: MAX [FORTH].
; Manual stack: ( n1 n2 --- max)
; Manual: Leaves the greatest of two numbers.
MAX_NFA:
	.byte	$83,"MA",$D8
	.word	MIN_NFA	; LFA: previous name field in this vocabulary chain
MAX:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	TDUP
	.word	LESS
	.word	ZBRAN,4	; Pop flag; if zero branch to $94F0 (offset +4 from operand cell)
	.word	SWAP
	.word	DROP
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: M* [FORTH].
; Manual stack: ( n1 n2 --- d )
; Manual: A mixed magnitude math operation which leaves the double number
; signed product of two signed numbers.
MSTAR_NFA:
	.byte	$82,"M",$AA
	.word	MAX_NFA	; LFA: previous name field in this vocabulary chain
MSTAR:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	TDUP
	.word	XORR
	.word	TOR
	.word	ABS
	.word	SWAP
	.word	ABS
	.word	USTAR
	.word	RFROM
	.word	DPM
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: M/ [FORTH].
; Manual stack: ( d n1 --- n2 n3 )
; Manual: A mixed magnitude math operator which leaves the signed remainder
; of n2 and signed quotient n3 from a double number dividend and divisor n1.
; The remainder takes its sign from the dividend.
MSLAS_NFA:
	.byte	$82,"M",$AF
	.word	MSTAR_NFA	; LFA: previous name field in this vocabulary chain
MSLAS:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	OVER
	.word	TOR
	.word	TOR
	.word	DABS
	.word	R
	.word	ABS
	.word	USLAS
	.word	RFROM
	.word	R
	.word	XORR
	.word	PM
	.word	SWAP
	.word	RFROM
	.word	PM
	.word	SWAP
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: * [FORTH].
; Manual stack: ( n1 n2 --- prod )
; Manual: Leaves the signed product of two signed numbers on the stack. Use .
; (dot) to print the result.
STAR_NFA:
	.byte	$81,$AA
	.word	MSLAS_NFA	; LFA: previous name field in this vocabulary chain
STAR:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	USTAR
	.word	DROP
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: /MOD [FORTH].
; Manual stack: ( n1 n2 --- rem quot )
; Manual: Leaves the remainder and signed quotient of n1/n2. The remainder
; has the sign of the dividend.
SLMOD_NFA:
	.byte	$84,"/MO",$C4
	.word	STAR_NFA	; LFA: previous name field in this vocabulary chain
SLMOD:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	TOR
	.word	STOD
	.word	RFROM
	.word	MSLAS
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: / [FORTH].
; Manual stack: ( n1 n2 --- quot )
; Manual: Leaves the signed quotient of n1/n2.
SLASH_NFA:
	.byte	$81,$AF
	.word	SLMOD_NFA	; LFA: previous name field in this vocabulary chain
SLASH:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	SLMOD
	.word	SWAP
	.word	DROP
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: MOD [FORTH].
; Manual stack: ( n1 n2 ---mod )
; Manual: Leaves the remainder of n1/n2, with the same sign as n1.
MOD_NFA:
	.byte	$83,"MO",$C4
	.word	SLASH_NFA	; LFA: previous name field in this vocabulary chain
MOD:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	SLMOD
	.word	DROP
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: */MOD [FORTH].
; Manual stack: ( n1 n2 n3 --- n4 n5 )
; Manual: Leaves the quotient n5 and remainder n4 of the operation n1*n2/n3
; on the stack. A 31-bit intermediate product is used as for */.
SSMOD_NFA:
	.byte	$85,"*/MO",$C4
	.word	MOD_NFA	; LFA: previous name field in this vocabulary chain
SSMOD:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	TOR
	.word	MSTAR
	.word	RFROM
	.word	MSLAS
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: */ [FORTH].
; Manual stack: ( n1 n2 n3 --- n4)
; Manual: Leaves the ratio n4=n1*n2/n3 where all are assigned 105 numbers.
; Retention of an intermediate 31-bit product permits greater accuracy than
; would be available with the sequence: n1 n2 * n3 /
SSLAS_NFA:
	.byte	$82,"*",$AF
	.word	SSMOD_NFA	; LFA: previous name field in this vocabulary chain
SSLAS:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	SSMOD
	.word	SWAP
	.word	DROP
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: M/MOD [FORTH].
; Manual stack: ( ud1 u2 --- u3 ud4)
; Manual: An unsigned mixed magnitude math operation which leaves a double
; quotient ud4 and remainder u3, from a double dividend u1 and single divisor
; u2.
MSLM_NFA:
	.byte	$85,"M/MO",$C4
	.word	SSLAS_NFA	; LFA: previous name field in this vocabulary chain
MSLM:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	TOR
	.word	ZERO
	.word	R
	.word	USLAS
	.word	RFROM
	.word	SWAP
	.word	TOR
	.word	USLAS
	.word	RFROM
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: BLOCK [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- a1 )
; Manual: This word is a FORTH mass storage primitive, which returns the
; address a1 of screen n1. If a disk file is open, the screen will be read
; into memory if required, before returning the address. The range of screens
; accessible is limited by the range 1 through the value specified in
; variable BMAX. BMAX is initialized to 16. As a result, no disk file can be
; larger than 16k, unless you change the value in BMAX to some number greater
; than 16. Only 16 continuous screens can be held in memory at one time, so
; additional time overhead will occur if you frequently access screens which
; are exactly 16 apart, that is, screens 1 and 17, or 2 and 18, etc. Once a
; screen is read in from mass storage, it remains in memory until it is
; over-written by a screen 16 or higher or 16 lower than it, or en
; EMPTYBUFFERS is performed. [See full entry in 64FORTH.TXT.]
BLOCK_NFA:
	.byte	$85,"BLOC",$CB
	.word	MSLM_NFA	; LFA: previous name field in this vocabulary chain
BLOCK:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: (LINE) [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 n2 --- a count )
; Manual: Converts the line number n1 and the screen n2 to the disk buffers
; address containing the data. A count of 64 indicates the full fine text
; length.
PLINE_NFA:
	.byte	$86,"(LINE",$A9
	.word	BLOCK_NFA	; LFA: previous name field in this vocabulary chain
PLINE:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: .LINE [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1/n2 --- )
; Manual: Prints on the terminal device, a line of text from the disk or
; cassette by its line and screen numbers. Trailing blanks are suppressed.
DLINE_NFA:
	.byte	$85,".LIN",$C5
	.word	PLINE_NFA	; LFA: previous name field in this vocabulary chain
DLINE:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: MESSAGE [FORTH].
; Manual stack: ( n1 --- )
; Manual: Prints the error message number n1 to the current output device.
; 64FORTH prints the error messages from ROM memory, and not from disk.
MESS_NFA:
	.byte	$87,"MESSAG",$C5
	.word	DLINE_NFA	; LFA: previous name field in this vocabulary chain
MESS:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	CLIT	; Push following inline byte, zero-extended
	.byte	(ERROR_TABLE_END-ERROR_TABLE)/2-1
	.word	MIN
	.word	ZERO
	.word	MAX
	.word	TWO
	.word	STAR
	.word	LIT,ERROR_TABLE
	.word	PLUS
	.word	AT
	.word	COUNT
	.word	TYPE
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: LOAD [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n --- )
; Manual: Begins interpretation of screen n. Loading will terminate at the
; end of screen or at ;S. See ;S and -->
LOAD_NFA:
	.byte	$84,"LOA",$C4
	.word	MESS_NFA	; LFA: previous name field in this vocabulary chain
LOAD:
    .word NO_C64
SERIAL_EMIT:
    .word *+2
    REQUIRE_CELLS 1
    lda 0,x
    jsr print_chr
    jmp POP

; ---------------------------------------------------------------------------
; Dictionary: ' [FORTH]; immediate (executes during compilation).
; Manual stack: ( --- a1 )
; Manual: Used in the form: ' nnnn Leaves the parameter field address of
; dictionary word nnnn. As a compiler directive, executes in a
; colon-definition to compile the address as a literal. If the word is not
; found after a search of CONTEXT and CURRENT, an appropriate error message
; is given. Pronounced "tick."
TICK_NFA:
	.byte	$C1,$A7
	.word	LOAD_NFA	; LFA: previous name field in this vocabulary chain
TICK:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	DFIND
	.word	ZEQU
	.word	ZERO
	.word	QERR
	.word	DROP
	.word	LITER
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: BACK [FORTH].
; Manual stack: ( a --- )
; Manual: Calculates the backward branch offset from HERE to address 2, and
; compiles into the next available dictionary memory address.
BACK_NFA:
	.byte	$84,"BAC",$CB
	.word	TICK_NFA	; LFA: previous name field in this vocabulary chain
BACK:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	HERE
	.word	SUBB
	.word	COMMA
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: BEGIN [FORTH]; immediate (executes during compilation).
; Manual stack: ( --- a n ) (compiling)
; Manual: Occurs in a colon-definition form: BEGIN ... UNTIL BEGIN ... AGAIN
; BEGIN ... WHILE ... REPEAT At run-time, BEGIN marks the start of a sequence
; that may be executed repeatedly. It serves as a return point from the
; corresponding UNTIL, a return to BEGIN will occur if the top of the stack
; is false; for AGAIN and REPEAT a return to BEGIN always occurs. At
; compile-time BEGIN leaves its return address and n for compiler error
; checking.
BEGIN_NFA:
	.byte	$C5,"BEGI",$CE
	.word	BACK_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	QCOMP
	.word	HERE
	.word	ONE
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ENDIF [FORTH]; immediate (executes during compilation).
; Manual stack: ( a n --- ) (compile)
; Manual: Occurs in a colon-definition in the form: IF...ELSE...ENDIF
; IF...ENDIF At run-time, ENDIF serves only as the destination of a forward
; branch from IF or ELSE. It marks the conclusion of the conditional
; structure. THEN is another name for ENDIF. See also IF and ELSE.
ENDIF_NFA:
	.byte	$C5,"ENDI",$C6
	.word	BEGIN_NFA	; LFA: previous name field in this vocabulary chain
ENDIF:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	QCOMP
	.word	TWO
	.word	QPAIR
	.word	HERE
	.word	OVER
	.word	SUBB
	.word	SWAP
	.word	STORE
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: DO [FORTH]; immediate (executes during compilation).
; Manual stack: ( n1 --- n2 ) (execute)
; Manual: ( a n --- ) (compile) Occurs in a colon-definition in form: DO ...
; LOOP DO ... +LOOP At run-time, DO begins a sequence with repetitive
; execution controlled by a loop limit n1 and an index with initial value of
; n2. DO removes these from the stack. Upon reaching LOOP the index is
; incremented by one. Until the new index equals or exceeds the limit,
; execution loops back to just after DO; otherwise the loop parameters are
; discarded and execution continues ahead. Both n1 and n2 are determined at
; run-time and may be the result of other operations. Within a loop "I" will
; copy the current value of the index to the stack. See I, LOOP, +LOOP,
; LEAVE. When compiling within the colon-definition, DO compiles (DO), leaves
; the following address a and n for later error checking.
DO_NFA:
	.byte	$C2,"D",$CF
	.word	ENDIF_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	COMP
	.word	PDO	; Inline CFA operand consumed by COMPILE
	.word	HERE
	.word	THREE
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: LOOP [FORTH]; immediate (executes during compilation).
; Manual stack: ( a n --- ) (compiling)
; Manual: Occurs in a colon-definition in form: DO ... LOOP At run-time, LOOP
; selectively controls branching back to the corresponding DO based on the
; loop index and limit. The loop index is incremented by one and compared to
; the limit. A branch back to DO occurs when the index equals or exceeds the
; limit. At that time, the parameters are discarded and execution continues
; ahead. At compile time, LOOP compiles (LOOP) and uses address a to
; calculate an offset to DO. n is used for error testing.
LOOP_NFA:
	.byte	$C4,"LOO",$D0
	.word	DO_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	THREE
	.word	QPAIR
	.word	COMP
	.word	PLOOP	; Inline CFA operand consumed by COMPILE
	.word	BACK
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: +LOOP [FORTH]; immediate (executes during compilation).
; Manual stack: ( n1 --- ) (run-time)
; Manual: ( a n2 --- ) (compile-time) Used in a colon definition in the form:
; DO ... n1 +LOOP. At run-time +LOOP selectively controls branching back to
; the corresponding DO based on n1, the loop index and the loop limit. The
; signed increment n1 is added to the index and the total compared to the
; limit. The branch back to DO occurs until the new index is equal to or
; greater than the limit (n1=0), or until the new index is equal to or less
; than the limit (n1=0). Upon exiting the loop, the parameters are discarded
; and the execution continues ahead.
PLUS_LOOP_NFA:
	.byte	$C5,"+LOO",$D0
	.word	LOOP_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	THREE
	.word	QPAIR
	.word	COMP
	.word	PPLOO	; Inline CFA operand consumed by COMPILE
	.word	BACK
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: UNTIL [FORTH]; immediate (executes during compilation).
; Manual stack: ( f --- ) (run-time)
; Manual: ( a n --- ) (compile) Occurs within a colon-definition in the form:
; BEGIN ... UNTIL 148 At run-time, UNTIL controls the conditional branch back
; to the corresponding BEGIN. If f is false, execution returns to just after
; BEGIN; if true execution continues ahead. At compile-time, UNTIL compiles
; (0BRANCH) and an offset from HERE to address n is used for error testing.
UNTIL_NFA:
	.byte	$C5,"UNTI",$CC
	.word	PLUS_LOOP_NFA	; LFA: previous name field in this vocabulary chain
UNTIL:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	ONE
	.word	QPAIR
	.word	COMP
	.word	ZBRAN,BACK	; First CFA is consumed by COMPILE; remaining cells resume the thread
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: AGAIN [FORTH]; immediate (executes during compilation).
; Manual stack: ( a n --- ) (compiling)
; Manual: Used in a colon-definition in the form: BEGIN ... AGAIN At
; run-time, AGAIN forces execution to return to the corresponding BEGIN.
; There is no effect on the stack. Execution can be terminated by pressing
; the RUN/STOP and RESTORE keys simultaneously.
AGAIN_NFA:
	.byte	$C5,"AGAI",$CE
	.word	UNTIL_NFA	; LFA: previous name field in this vocabulary chain
AGAIN:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	ONE
	.word	QPAIR
	.word	COMP
	.word	BRAN	; Inline CFA operand consumed by COMPILE
	.word	BACK
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: REPEAT [FORTH]; immediate (executes during compilation).
; Manual stack: ( a n --- ) (compiling)
; Manual: Used with a colon-definition in the form: BEGIN ... WHILE ...
; REPEAT At run-time, REPEAT forces an unconditional branch back to just
; after the corresponding BEGIN. At compile-time, REPEAT compiles BRANCH and
; the offset from HERE to address n is used for error testing.
REPEAT_NFA:
	.byte	$C6,"REPEA",$D4
	.word	AGAIN_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	TOR
	.word	TOR
	.word	AGAIN
	.word	RFROM
	.word	RFROM
	.word	TWO
	.word	SUBB
	.word	ENDIF
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: IF [FORTH]; immediate (executes during compilation).
; Manual stack: ( f --- ) (run-time)
; Manual: ( --- a n ) (compile) Occurs in a colon-definition form: IF (tp)...
; ENDIF IF (tp)... ELSE (fp) ... ENDIF At run-time, IF selects execution
; based on a boolean flag. If f is true (non-zero), execution continues ahead
; through the true part. If f is false (zero), execution skips until just
; after ELSE to execute the false part. After either part, execution resumes
; after ENDIF. ELSE and its false part are optional; if missing, false,
; execution skips to after ENDIF.
IF_NFA:
	.byte	$C2,"I",$C6
	.word	REPEAT_NFA	; LFA: previous name field in this vocabulary chain
IF:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	COMP
	.word	ZBRAN,HERE	; First CFA is consumed by COMPILE; remaining cells resume the thread
	.word	ZERO
	.word	COMMA
	.word	TWO
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ELSE [FORTH]; immediate (executes during compilation).
; Manual stack: ( a1 n1 --- a2 n2 ) (compiling)
; Manual: Occurs within a colon-definition in the form: IF ... ELSE ... ENDIF
; 124 At run-time, ELSE executes after the true part following IF. ELSE
; forces execution to skip over the following false part and resumes
; execution after ENDIF. It has no stack effect. At compile-time, ELSE
; emplaces BRANCH reserving a branch offset and leaves the address a2 and n2
; for error testing. ELSE also resolves the pending forward branch from IF by
; calculating the offset from a1 to HERE and storing at a1.
ELSE_NFA:
	.byte	$C4,"ELS",$C5
	.word	IF_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	TWO
	.word	QPAIR
	.word	COMP
	.word	BRAN	; Inline CFA operand consumed by COMPILE
	.word	HERE
	.word	ZERO
	.word	COMMA
	.word	SWAP
	.word	TWO
	.word	ENDIF
	.word	TWO
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: WHILE [FORTH]; immediate (executes during compilation).
; Implementation: Compilation: compile IF after the BEGIN destination, then
; rearrange control markers for REPEAT.
WHILE_NFA:
	.byte	$C5,"WHIL",$C5
	.word	ELSE_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	IF
	.word	TWOP
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: SPACES [FORTH].
; Manual stack: ( n --- )
; Manual: Transmits n ASCII blanks to the output device.
SPACS_NFA:
	.byte	$86,"SPACE",$D3
	.word	WHILE_NFA	; LFA: previous name field in this vocabulary chain
SPACS:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	ZERO
	.word	MAX
	.word	QDUP
	.word	ZBRAN,$C	; Pop flag; if zero branch to $979A (offset +12 from operand cell)
	.word	ZERO
	.word	PDO
	.word	SPACE
	.word	PLOOP,$FFFC	; Increment loop index; if continuing branch to $9794 (offset -4 from operand cell)
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: <# [FORTH].
; Manual: Begins the number conversion for formatting using the words: <# #
; #S #>. The conversion is done on a double number producing text at PAD.
BDIGS_NFA:
	.byte	$82,"<",$A3
	.word	SPACS_NFA	; LFA: previous name field in this vocabulary chain
BDIGS:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	PAD
	.word	HLD
	.word	STORE
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: #> [FORTH].
; Manual stack: ( d --- a count )
; Manual: Terminates numeric output conversion by dropping d, leaving the
; text address and character count suitable for TYPE.
EDIGS_NFA:
	.byte	$82,"#",$BE
	.word	BDIGS_NFA	; LFA: previous name field in this vocabulary chain
EDIGS:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	DROP
	.word	DROP
	.word	HLD
	.word	AT
	.word	PAD
	.word	OVER
	.word	SUBB
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: SIGN [FORTH].
; Manual stack: ( n d --- d )
; Manual: Stores an ASCII "-" sign just before a converted numeric output
; string in the text output buffer when n is negative. N is discarded but
; double number d is maintained. Must be used between <# and #>.
SIGN_NFA:
	.byte	$84,"SIG",$CE
	.word	EDIGS_NFA	; LFA: previous name field in this vocabulary chain
SIGN:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	ROT
	.word	ZLESS
	.word	ZBRAN,7	; Pop flag; if zero branch to $97D8 (offset +7 from operand cell)
	.word	CLIT	; Push following inline byte, zero-extended
	.byte	"-"
	.word	HOLD
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: # [FORTH].
; Manual stack: ( d1 --- d2 )
; Manual: Generates from a double number d1, the next ASCII character placed
; in an output string. Result d2 is the quotient after division by BASE, and
; is maintained for further processing. Used between <# and #>. See #S. 101
DIG_NFA:
	.byte	$81,$A3
	.word	SIGN_NFA	; LFA: previous name field in this vocabulary chain
DIG:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	BASE
	.word	AT
	.word	MSLM
	.word	ROT
	.word	CLIT	; Push following inline byte, zero-extended
	.byte	9
	.word	OVER
	.word	LESS
	.word	ZBRAN,7	; Pop flag; if zero branch to $97F8 (offset +7 from operand cell)
	.word	CLIT	; Push following inline byte, zero-extended
	.byte	7
	.word	PLUS
	.word	CLIT	; Push following inline byte, zero-extended
	.byte	"0"
	.word	PLUS
	.word	HOLD
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: #S [FORTH].
; Stack (from code): ( ud -- 0 0 )
; Manual: Generates ASCII text in the text output buffer, by the use of #,
; until a zero double number n2 results. Used between <# and #>.
DIGS_NFA:	.byte	$82,"#",$D3
	.word	DIG_NFA	; LFA: previous name field in this vocabulary chain
DIGS:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	DIG
	.word	TDUP
	.word	ORR
	.word	ZEQU
	.word	ZBRAN,$FFF6	; Pop flag; if zero branch to $9808 (offset -10 from operand cell)
	.word	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: D.R [FORTH].
; Manual stack: ( d n --- )
; Manual: Prints a signed double number d right aligned in a field n
; characters wide.
DDOTR_NFA:
	.byte	$83,"D.",$D2
	.word	DIGS_NFA	; LFA: previous name field in this vocabulary chain
DDOTR:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	TOR
	.word	SWAP
	.word	OVER
	.word	DABS
	.word	BDIGS
	.word	DIGS
	.word	SIGN
	.word	EDIGS
	.word	RFROM
	.word	OVER
	.word	SUBB
	.word	SPACS
	.word	TYPE
	.word	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: D. [FORTH].
; Manual stack: ( d --- )
; Manual: Prints a signed double number from a 32-bit two's complement value.
; The high-order 16 bits are most accessible on the stack. Conversion is
; performed according to the current BASE. A blank follows. Pronounced "D
; dot." 120
DDOT_NFA:
	.byte	$82,"D",$AE
	.word	DDOTR_NFA	; LFA: previous name field in this vocabulary chain
DDOT:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	ZERO
	.word	DDOTR
	.word	SPACE
	.word	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: .R [FORTH].
; Manual stack: ( n1 n2 --- )
; Manual: Prints the number n1 right aligned in a field whose width is n2. No
; following blank is printed.
DOTR_NFA:
	.byte	$82,".",$D2
	.word	DDOT_NFA	; LFA: previous name field in this vocabulary chain
DOTR:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	TOR
	.word	STOD
	.word	RFROM
	.word	DDOTR
	.word	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: . [FORTH].
; Manual stack: ( n --- )
; Manual: Prints a number from a signed 16-bit two's complement value,
; converted according to the numeric BASE. Followed by one blank space.
; Pronounced "dot." This is a vectored word.
DOT_NFA:
	.byte	$81,$AE
	.word	DOTR_NFA	; LFA: previous name field in this vocabulary chain
DOT:
	.word	DOVEC	; CFA: vectored word; dispatch through UP+$32+offset
	.byte	14	; Vector byte offset 14 from I/O (UP+$32)

PDOT:
	.word	DOCOL
	.word	STOD
	.word	DDOT
	.word	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: ? [FORTH].
; Manual stack: ( a --- )
; Manual: Prints the value contained at the address in free format according
; to the current base.
QUES_NFA:
	.byte	$81,$BF
	.word	DOT_NFA	; LFA: previous name field in this vocabulary chain
QUES:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	AT
	.word	DOT
	.word	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: LIST [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n --- )
; Manual: Displays the ASCII text of screen n on the selected output device.
; SCR contains the screen number during and after this process.
LIST_NFA:
	.byte	$84,"LIS",$D4
	.word	QUES_NFA	; LFA: previous name field in this vocabulary chain
LIST:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: VLIST [FORTH].
; Manual: Lists the names of the definitions in the context vocabulary. The
; RUN/STOP key will end the listing. Hitting any key will stop the scrolling
; and any key will continue the scrolling.
VLIST_NFA:
	.byte	$85,"VLIS",$D4
	.word	LIST_NFA	; LFA: previous name field in this vocabulary chain
VLIST:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	CONT
	.word	AT
	.word	AT
	.word	CR
	.word	DUP
	.word	IDDOT
	.word	TAB
	.word	PFA
	.word	LFA
	.word	QTER
	.word	ZBRAN,$D	; Pop flag; if zero branch to $98E9 (offset +13 from operand cell)
	.word	KEY
	.word	CLIT	; Push following inline byte, zero-extended
	.byte	3
	.word	SUBB
	.word	ZBRAN,$C	; Pop flag; if zero branch to $98F3 (offset +12 from operand cell)
	.word	AT
	.word	DUP
	.word	ZEQU
	.word	ZBRAN,$FFDD	; Pop flag; if zero branch to $98CE (offset -35 from operand cell)
	.word	DROP
	.word	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: READS [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1/n2 --- )
; Manual: Used to READ a group of screens from cassette, into screen n1 for a
; count of n2 screens. Cannot be made to read screens from disk, since each
; file must have a unique name.
READS_NFA:
	.byte	$85,"READ",$D3
	.word	VLIST_NFA	; LFA: previous name field in this vocabulary chain
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: WRITES [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1/n2 --- )
; Manual: Screens n1 through n1 + n2 will be written to cassette.
WRITES_NFA:
	.byte	$86,"WRITE",$D3
	.word	READS_NFA	; LFA: previous name field in this vocabulary chain
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: LOADS [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: A mass storage word, used to load from cassette a sequence of
; screens into screen butter one, and then a one (1) load is performed. This
; is mainly a hold over from VICFORTH, and was used to minimize the number of
; buffers required to load a program from cassette.
LOADS_NFA:
	.byte	$85,"LOAD",$D3
	.word	WRITES_NFA	; LFA: previous name field in this vocabulary chain
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: EM [FORTH].
; IMNOTWOPR: implemented by the serial shell.
; Original C64 manual stack: ( --- a1 )
; Manual: A SYSTEM variable, which holds an address one byte higher than the
; highest user address available to the FORTH dictionary. Changing this
; address will cause both FORTH and the Commodore KERNEL to think the memory
; size has changed. The contents of EM must not be in creased, however, as
; 64FORTH uses all higher memory locations.
EM_NFA:
	.byte	$82,"E",$CD
	.word	LOADS_NFA	; LFA: previous name field in this vocabulary chain
EM:
    .word DOCON
    .word memory_limit

; ---------------------------------------------------------------------------
; Dictionary: THRU [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1/n2 --- )
; Manual: Loads screen n1 THRU screen n2. If a disk file is open, the screens
; will automatically be read in from disk. If used on a cassette based
; system, the screens must be READ into the screen buffers before the THRU
; word can be used.
THRU_NFA:
	.byte	$84,"THR",$D5
	.word	EM_NFA	; LFA: previous name field in this vocabulary chain
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: SETNAM [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( a1/n1 --- )
; Manual: A KERNAL system call, used to set the system filename to the string
; at address a1, for length n1 characters.
SETNAM_NFA:
	.byte	$86,"SETNA",$CD
	.word	$84C	; LFA: previous name field in this vocabulary chain
SETNAM:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: NAME [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- (text) )
; Manual: Accepts A the string of text following, delimited by an up arrow
; "^", into the FN buffer, and performs a system call to the SETNAM KERNEL
; routine.
NAME_NFA:
	.byte	$84,"NAM",$C5
	.word	THRU_NFA	; LFA: previous name field in this vocabulary chain
NAME:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: TAB [FORTH].
; Manual stack: ( --- )
; Manual: Tabs to the next tab position on the screen. Used by VLIST and
; several other words requiring output formatting.
TAB_NFA:
	.byte	$83,"TA",$C2
	.word	NAME_NFA	; LFA: previous name field in this vocabulary chain
TAB:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	CLIT	; Push following inline byte, zero-extended
	.byte	$A
	.word	OUT
	.word	AT
	.word	OVER
	.word	MOD
	.word	SUBB
	.word	ZERO
	.word	MAX
	.word	DUP
	.word	OUT
	.word	AT
	.word	PLUS
	.word	CLIT	; Push following inline byte, zero-extended
	.byte	30
	.word	GREAT
	.word	ZBRAN,$A	; Pop flag; if zero branch to $99D2 (offset +10 from operand cell)
	.word	DROP
	.word	CR
	.word	BRAN,4	; Jump to $99D4 (offset +4 from operand cell)
	.word	SPACS
	.word	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: TEXT [FORTH].
; Manual stack: ( c1 --- )
; Manual: Accepts text from the input stream delimited by character c1. The
; text accepted is placed at PAD.
TEXT_NFA:
	.byte	$84,"TEX",$D4
	.word	TAB_NFA	; LFA: previous name field in this vocabulary chain
TEXT:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	HERE
	.word	CSLL
	.word	ONEP
	.word	BLANK
	.word	WORD
	.word	HERE
	.word	PAD
	.word	CSLL
	.word	ONEP
	.word	CMOVE
	.word	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: LINE [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- a1 )
; Manual: Returns address all of line n1 in current edit screen as specified
; by variable SCR.
LINE_NFA:
	.byte	$84,"LIN",$C5
	.word	TEXT_NFA	; LFA: previous name field in this vocabulary chain
LINE:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: 2DUP [FORTH].
; Manual stack: ( n1/n2 --- n1/n2/n1/n2 )
; Manual: Duplicates the top two single length elements on the data stack.
; Pronounced "two dup."
TDUP_NFA:
	.byte	$84,"2DU",$D0
	.word	LINE_NFA	; LFA: previous name field in this vocabulary chain
TDUP:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	OVER
	.word	OVER
	.word	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: 2SWAP [FORTH].
; Manual stack: ( n1/n2/n3/n4 --- n3/n4/n1/n2 )
; Manual: Exchanges the order of the top two pairs of elements on the data
; stack.
TSWAP_NFA:
	.byte	$85,"2SWA",$D0
	.word	TDUP_NFA	; LFA: previous name field in this vocabulary chain
TSWAP:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	ROT
	.word	TOR
	.word	ROT
	.word	RFROM
	.word	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: U. [FORTH].
; Manual stack: ( u1 --- )
; Manual: Displays the unsigned number in the current BASE on the screen,
; with one trailing blank following the free formatted number.
UDOT_NFA:
	.byte	$82,"U",$AE
	.word	TSWAP_NFA	; LFA: previous name field in this vocabulary chain
UDOT:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	ZERO
	.word	DDOT
	.word	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: H. [FORTH].
; Manual stack: ( n1 --- )
; Manual: Prints the value n1 to the current output device in the HEXADECIMAL
; number base and in an unsigned format.
HDOT_NFA:
	.byte	$82,"H",$AE
	.word	UDOT_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	BASE
	.word	AT
	.word	SWAP
	.word	HEX
	.word	UDOT
	.word	BASE
	.word	STORE
	.word	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: DUMP [FORTH].
; Manual stack: ( a1/n1 --- )
; Manual: The contents of memory starting at address a1 for a length of n1
; bytes is displayed on the screen, in the current number base, with 8 bytes
; per line, preceeded by the address of the first byte in the line.
DUMP_NFA:
	.byte	$84,"DUM",$D0
	.word	HDOT_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	OVER
	.word	PLUS
	.word	SWAP
	.word	CR
	.word	PDO
	.word	I
	.word	ZERO
	.word	CLIT	; Push following inline byte, zero-extended
	.byte	5
	.word	DDOTR
	.word	I
	.word	CLIT	; Push following inline byte, zero-extended
	.byte	8
	.word	PLUS
	.word	I
	.word	PDO
	.word	I
	.word	CAT
	.word	CLIT	; Push following inline byte, zero-extended
	.byte	4
	.word	DOTR
	.word	PLOOP,$FFF5	; Increment loop index; if continuing branch to $9A8B (offset -11 from operand cell)
	.word	CR
	.word	CLIT	; Push following inline byte, zero-extended
	.byte	8
	.word	PPLOO,$FFD8	; Add stack increment; if continuing branch to $9A77 (offset -40 from operand cell)
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; SCREEN / LINE EDITOR
; ---------------------------------------------------------------------------
; Dictionary: #LOCATE [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- n1/n2 )
; Manual: An editor primitive which returns the cursor line as n1 and the
; character position on the line as n2.
NLOCAT_NFA:
	.byte	$87,"#LOCAT",$C5
	.word	$84C	; LFA: previous name field in this vocabulary chain
NLOCAT:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: BMOV [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( a1 --- )
; Manual: An editor primitive, (that moves the contents of PAD for C/L
; characters to address a1) if PAD contains text other than a null in the
; first character position (pad+1), otherwise, nothing is done.
BMOV_NFA:
	.byte	$84,"BMO",$D6
	.word	NLOCAT_NFA	; LFA: previous name field in this vocabulary chain
BMOV:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: PADF [EDITOR].
; Manual stack: ( --- a1 )
; Manual: An editor buffer, 65 characters long used to hold the strings of
; text searched for the find buffer.
PADF_NFA:
	.byte	$84,"PAD",$C6
	.word	BMOV_NFA	; LFA: previous name field in this vocabulary chain
PADF:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	PAD
	.word	CLIT	; Push following inline byte, zero-extended
	.byte	80
	.word	PLUS
	.word	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: PADI [EDITOR].
; Manual stack: (--- a1 )
; Manual: An editor buffer 65 characters long used to hold the strings of
; text inserted: the insert buffer.
PADI_NFA:
	.byte	$84,"PAD",$C9
	.word	PADF_NFA	; LFA: previous name field in this vocabulary chain
PADI:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	PADF
	.word	CLIT	; Push following inline byte, zero-extended
	.byte	80
	.word	PLUS
	.word	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: !CUR [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Moves edit cursor to character position 0 in current edit screen if
; n1 is in the range 0 to B/BUF-1. !CUR will only change the current cursor
; position if 0 is within the valid range. Causes the current edit window
; around the cursor to be viewed in the upper 16 lines of the display.
STOCUR_NFA:
	.byte	$84,"!CU",$D2
	.word	PADI_NFA	; LFA: previous name field in this vocabulary chain
STOCUR:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: L# [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- n1 )
; Manual: An editor primitive, which returns the fine number of the line
; which currently contains the cursor.
LNUM_NFA:
	.byte	$82,"L",$A3
	.word	STOCUR_NFA	; LFA: previous name field in this vocabulary chain
LNUM:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: #LEAD [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- a1/n1 )
; Manual: An editor primitive, which returns the address of the cursor line
; as a1, and the number of characters before the cursor on the line as n1.
NLEAD_NFA:
	.byte	$85,"#LEA",$C4
	.word	LNUM_NFA	; LFA: previous name field in this vocabulary chain
NLEAD:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: #LAG [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- a1/n1 )
; Manual: An editor primitive, which returns the address of the cursor as a1,
; and the number of characters remaining on the following the cursor as n1.
NLAG_NFA:
	.byte	$84,"#LA",$C7
	.word	NLEAD_NFA	; LFA: previous name field in this vocabulary chain
NLAG:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: -MOVE [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( a1/n1 --- )
; Manual: Moves c/l characters of text from address a1 to line n1 of current
; edit screen. The screen is updated.
DMOVE_NFA:
	.byte	$85,"-MOV",$C5
	.word	NLAG_NFA	; LFA: previous name field in this vocabulary chain
DMOVE:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: H [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: An editor word, which causes a copy of the line currently
; containing the cursor to be moved to the insert buffer PADI. The text can
; later be reinserted with "U", or "I" or "P".
HH_NFA:
	.byte	$81,$C8
	.word	DMOVE_NFA	; LFA: previous name field in this vocabulary chain
HH:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: K [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: An editor word, which erases or "KILLS" the current cursor line.
; The line is filled with blanks, but no text compression occurs.
KK_NFA:
	.byte	$81,$CB
	.word	HH_NFA	; LFA: previous name field in this vocabulary chain
KK:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: S [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: An editor word, causes all lines from the current cursor line down
; to be SPREAD down, by one line. Line 15 will be lost, and the current
; cursor line will become blank.
SS_NFA:
	.byte	$81,$D3
	.word	KK_NFA	; LFA: previous name field in this vocabulary chain
SS:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: X [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: An editor word which deletes the current cursor line, placing it in
; PADI--the insert buffer. All lower lines are moved up to fill the space.
; The text may be put back into the edit screen, with U <RETURN>, after
; moving the cursor to the desired line.
XX_NFA:
	.byte	$81,$D8
	.word	SS_NFA	; LFA: previous name field in this vocabulary chain
XX:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: C [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: An editor primitive, used to move the cursor a RELATIVE amount
; within the current edit screen. The signed value n1 is added to the current
; cursor location, and If the value is within the current screen, the cursor
; location is updated to the new value. Otherwise the cursor location is
; unchanged. 115
CC_NFA:
	.byte	$81,$C3
	.word	XX_NFA	; LFA: previous name field in this vocabulary chain
CC:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: T [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: An editor word, moves the cursor to the beginning of line n11 on
; the current edit screen. N1 is in the range 0 to 15.
TT_NFA:
	.byte	$81,$D4
	.word	CC_NFA	; LFA: previous name field in this vocabulary chain
TT:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: GTEXT [EDITOR].
; Manual stack: ( --- )
; Manual: An editor primitive. accepts text from the input stream, until a
; delimiting "^" is encountered, or the (RETURN) key is pressed. The text is
; placed at address a1, for a length of 65 characters.
GTEXT_NFA:
	.byte	$85,"GTEX",$D4
	.word	TT_NFA	; LFA: previous name field in this vocabulary chain
GTEXT:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	CLIT	; Push following inline byte, zero-extended
	.byte	"^"
	.word	TEXT
	.word	BMOV
	.word	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: P [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Implementation: Editor: parse the following text into PADI, then replace
; the current line using PP.
PP_NFA:
	.byte	$81,$D0
	.word	GTEXT_NFA	; LFA: previous name field in this vocabulary chain
PP:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: U [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- (text) )
; Manual: An editor word which places the (text) following U under the
; current cursor line. (text) is optional.
UU_NFA:
	.byte	$81,$D5
	.word	PP_NFA	; LFA: previous name field in this vocabulary chain
UU:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: TOP [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual: Sends the cursor to the top left corner of the screen--the home
; position.
TOP_NFA:
	.byte	$83,"TO",$D0
	.word	UU_NFA	; LFA: previous name field in this vocabulary chain
TOP:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: COPY [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1/n2 --- )
; Manual: Copies screen n1 to screen n2, thereby creating a duplicate screen.
EDITOR_COPY_NFA:
	.byte	$84,"COP",$D9
	.word	TOP_NFA	; LFA: previous name field in this vocabulary chain
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: MATCH [EDITOR].
; Implementation: Search candidate addresses with (MATCH), retaining the
; pattern address/length across the loop. Return a found flag and a
; cursor-advance count; 1LINE uses that count to update R#.
MATCH_NFA:
	.byte	$85,"MATC",$C8
	.word	EDITOR_COPY_NFA	; LFA: previous name field in this vocabulary chain
MATCH:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	TOR
	.word	TOR
	.word	TDUP
	.word	RFROM
	.word	RFROM
	.word	TSWAP
	.word	OVER
	.word	PLUS
	.word	SWAP
	.word	PDO
	.word	TDUP
	.word	I
	.word	SWAP
	.word	PMATCH
	.word	ZBRAN,$1A	; Pop flag; if zero branch to $9CD5 (offset +26 from operand cell)
	.word	TOR
	.word	TDROP
	.word	RFROM
	.word	SUBB
	.word	I
	.word	SWAP
	.word	SUBB
	.word	ZERO
	.word	SWAP
	.word	ZERO
	.word	ZERO
	.word	LEAVE
	.word	PLOOP,$FFDA	; Increment loop index; if continuing branch to $9CB1 (offset -38 from operand cell)
	.word	TDROP
	.word	SWAP
	.word	ZEQU
	.word	SWAP
	.word	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: 1LINE [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Implementation: ( -- found ) Search from the cursor to the end of its line
; for PADF text, update R# by the returned advance, and leave the match flag.
ONELIN_NFA:
	.byte	$85,"1LIN",$C5
	.word	MATCH_NFA	; LFA: previous name field in this vocabulary chain
ONELIN:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: (F) [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: This is a low level editor primitive, which searches for the next
; occurence of the text in the PADF buffer. Not normally used by the user,
; but could be useful if the editor was being expanded with additional
; commands.
PFF_NFA:
	.byte	$83,"(F",$A9
	.word	ONELIN_NFA	; LFA: previous name field in this vocabulary chain
PFF:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: DEL [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: An editor primitive, which deletes n1 characters before the cursor;
; clips at the beginning of the screen, to prevent deleting off the screen.
; Text to the right of the cursor on the current line will be moved left to
; fill the space of the deleted characters.
DEL_NFA:
	.byte	$83,"DE",$CC
	.word	PFF_NFA	; LFA: previous name field in this vocabulary chain
DEL:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: F [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- (text)
; Manual: An editor word which finds the first occurence of (text) following
; an "F" command. Starts at the current cursor location. (text) is optional,
; and "F (return)" will find the next occurence of the last text searched
; for.
FF_NFA:
	.byte	$81,$C6
	.word	DEL_NFA	; LFA: previous name field in this vocabulary chain
FF:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: E [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: An editor word, used after an "F" command, to ERASE the text just
; found. Deletes characters for the length of the text in the find buffer.
EE_NFA:
	.byte	$81,$C5
	.word	FF_NFA	; LFA: previous name field in this vocabulary chain
EE:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: D [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- (text) )
; Manual: Deletes the first occurence of (text) following the D command and
; then searches from the edit cursor until the end of the screen. (text) is
; optional, and if omitted, will cause D to delete the same string as used
; previously.
EDITOR_D_NFA:
	.byte	$81,$C4
	.word	EE_NFA	; LFA: previous name field in this vocabulary chain
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: TILL [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Implementation: Editor: read a search string, locate it on the current
; line, and delete the span from the old cursor to the resulting cursor.
; PFF handles a failed search.
EDITOR_TILL_NFA:
	.byte	$84,"TIL",$CC
	.word	EDITOR_D_NFA	; LFA: previous name field in this vocabulary chain
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: (I) [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: A low level editor primitive, which inserts the character string
; held in PADI, into the next text screen at the current location specified
; by the contents of R#. Potentially useful for future expansion of the
; editor.
PII_NFA:
	.byte	$83,"(I",$A9
	.word	EDITOR_TILL_NFA	; LFA: previous name field in this vocabulary chain
PII:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: I [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- (text) )
; Manual: An editor word, causes (text) to be inserted at the current
; location of the cursor, with all text following the cursor being moved over
; to make room. Text on the cursor line too long for the line after the
; insert will be LOST. (text) is optional, and use of "I" without following
; text, causes the current contents of PADI the insert buffer to be inserted.
II_NFA:
	.byte	$81,$C9
	.word	PII_NFA	; LFA: previous name field in this vocabulary chain
II:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: R [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- (text) )
; Manual: An editor command, replaces the string just found with the "F"
; command with the (text) following "R" command. (text) is optional, and if
; omitted, will cause a replace with the last text used in the replace
; command.
EDITOR_R_NFA:
	.byte	$81,$D2
	.word	II_NFA	; LFA: previous name field in this vocabulary chain
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: N [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- a1 ) (assembling)
; Manual: Used in a code-definition in the form: N1 - sta, or n2 = )Y adc, A
; constant which leaves the address of a 9 byte workspace in z-page. Within a
; single code definition, free use may be made over the range N-1 through
; N-7.
NN_NFA:
	.byte	$81,$CE
	.word	EDITOR_R_NFA	; LFA: previous name field in this vocabulary chain
NN:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: B [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: An editor operation, which causes the edit to be moved to the
; previous screen. Pronounced "back." 112
BB_NFA:
	.byte	$81,$C2
	.word	NN_NFA	; LFA: previous name field in this vocabulary chain
BB:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: +SCR [EDITOR].
; Manual stack: ( n1 --- )
; Manual: Adds the signed value n1 to the current editor screen number, and
; clips the result to within the currently specified valid screen range, 1 to
; BMAX.
PSCR_NFA:
	.byte	$84,"+SC",$D2
	.word	BB_NFA	; LFA: previous name field in this vocabulary chain
PSCR:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	SCR
	.word	AT
	.word	PLUS
	.word	ONE
	.word	MAX
	.word	BMAX
	.word	AT
	.word	MIN
	.word	SCR
	.word	STORE
	.word	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: WIPE [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: An editor word that causes the current editor screen to be cleared
; to blanks.
EDITOR_WIPE_NFA:
	.byte	$84,"WIP",$C5
	.word	PSCR_NFA	; LFA: previous name field in this vocabulary chain
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: M [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1/n2 --- )
; Manual: An editor line MOVE word used to move the line currently containing
; the cursor to screen n1, under line n2.
EDITOR_M_NFA:
	.byte	$81,$CD
	.word	EDITOR_WIPE_NFA	; LFA: previous name field in this vocabulary chain
EDITOR_MOVE:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: V [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: Causes a VIEW of the current edit screen, around the currently
; specified cursor location. 149
VV_NFA:
	.byte	$81,$D6
	.word	EDITOR_M_NFA	; LFA: previous name field in this vocabulary chain
VV:
EDITOR_KEY_F1:
EDITOR_KEY_F3:
EDITOR_KEY_F5:
EDITOR_KEY_RIGHT:
EDITOR_KEY_LEFT:
EDITOR_KEY_DOWN:
EDITOR_KEY_UP:
EDITOR_KEY_F8:
EDITOR_KEY_F6:
EDITOR_KEY_CBM_Y:
EDITOR_KEY_CBM_Z:
EDITOR_KEY_CBM_G:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: EDIT [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Enters the split screen editor, on screen n1. The EDITOR is
; selected, and the editor capture table is enabled. See the EDITOR
; documentation, for further information on editor commands.
EDIT_NFA:
	.byte	$84,"EDI",$D4
	.word	DUMP_NFA	; LFA: previous name field in this vocabulary chain
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: ASCII [FORTH]; immediate (executes during compilation).
; Manual stack: ( --- t n1 )
; Manual: Accepts the word following ASCII, and returns the ASCII value of
; the first character of the word on the data stack.
ASCII_NFA:
	.byte	$C5,"ASCI",$C9
	.word	EDIT_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	BL
	.word	WORD
	.word	HERE
	.word	ONEP
	.word	CAT
	.word	LITER
	.word	SEMIS	; Return to caller thread

; ===========================================================================
; C64 MACHINE-CODE and FILE / SERIAL I/O BRIDGES
; ===========================================================================

; ----------------------------------------------------------------------------
; Dictionary: SYS [SYSTEM].
; Manual stack: ( (f1)/n1/n2/n3/a1 --- (f1)/n4/n5/n6 )
; Manual: A SYSTEM primitive used to allow calling assembly language
; subroutines. Calls routine at address a1, passing registers A, X, and Y, as
; n1, n2, and n3. The flag (f1) is optional, and if included, sets the state
; of the carry flag to clear for a zero value, or sets for non-zero values.
; Register values A, X, and Y, are returned as n4, n5, and n6, after the
; subroutine has completed. Flag (f1) is returned unmodified if included. The
; contents of the processor status register is returned after a SYS in the
; ASSEMBLER variable N.
SYS_NFA:
	.byte	$83,"SY",$D3
	.word	SETNAM_NFA	; LFA: previous name field in this vocabulary chain
; MACHINE-CODE BRIDGE. Stack input is (carry A X Y address), with address on
; top. Only low bytes supply registers; the optional carry cell is inspected
; but retained. Save Forth X, call through SYS_TRAMPOLINE, then replace low bytes of
; the A/X/Y cells with returned registers, save processor status in N, and
; drop address. High bytes of register cells are not cleared.
SYS:
	.word	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 5
	stx	XSAVE
	lda	0,X
	sta	NXTMP
	lda	1,X
	sta	NXTMP+1
	ldy	2,X
	lda	4,X
	sta	N
	lda	8,X
	bne	SYS_SET_CARRY
	clc
	bcc	SYS_CALL
SYS_SET_CARRY:
	sec
SYS_CALL:
	lda	6,X
	ldx	N
	jsr	SYS_TRAMPOLINE
	PHP
	stx	N
	ldx	XSAVE
	sta	6,X
	lda	N
	sta	4,X
	sty	2,X
	pla
	sta	N
	jmp	POP

; Indirect jsr trampoline: SYS uses jsr here, then jmp (NXTMP) lets the
; target rts return directly to SYS.
SYS_TRAMPOLINE:
	jmp	(NXTMP)

; ----------------------------------------------------------------------------
; Dictionary: READ [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Used to read a screen from cassette, into screen number n1. Will
; read screen from cassette with names, by specifying a name with the NAME
; command prior to READ. The variables D# and F# are used to determine which
; device and file number are used to read from. Therefore, it is possible to
; read files from disk.
READ_NFA:
	.byte	$84,"REA",$C4
	.word	ASCII_NFA	; LFA: previous name field in this vocabulary chain
READ:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: FSET [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: A low level file control word which performs a SETLFS system call
; with the current values of D# and F#. Used by READ and WRITE. 129
FSET_NFA:
	.byte	$84,"FSE",$D4
	.word	SYS_NFA	; LFA: previous name field in this vocabulary chain
FSET:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: SETLFS [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1/n2/n3 --- )
; Manual: A KERNAL system call, sets the logical file with file number n1,
; device number n2, and secondary command n3 into the KERNEL operating
; system.
SETLFS_NFA:
	.byte	$86,"SETLF",$D3
	.word	FSET_NFA	; LFA: previous name field in this vocabulary chain
SETLFS:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: 3DROP [FORTH].
; Manual stack: ( n1/n2/n3 --- )
; Manual: A code-saving word, which drops three arguments from the data
; stack. Used by several system call words.
THDROP_NFA:
	.byte	$85,"3DRO",$D0
	.word	READ_NFA	; LFA: previous name field in this vocabulary chain
THDROP:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	TDROP
	.word	DROP
	.word	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: OPEN [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: A KERNEL system call, which opens a channel as previously specified
; with the SETNAM and SETLFS commands.
OPEN_NFA:
	.byte	$84,"OPE",$CE
	.word	SETLFS_NFA	; LFA: previous name field in this vocabulary chain
OPEN:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: SLOAD [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( a1 --- )
; Manual: A KERNEL system call, which loads the file specified by currently
; selected file name from the currently selected device into memory starting
; at address a1. This word is used after performing a NAME and SETLFS
; operation.
SLOAD_NFA:
	.byte	$85,"SLOA",$C4
	.word	OPEN_NFA	; LFA: previous name field in this vocabulary chain
SLOAD:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: SAVE [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( a1/n1 --- )
; Manual: Saves the data or program starting at address a1, for a length of
; n1 bytes, to the currently open mass storage device.
SAVE_NFA:
	.byte	$84,"SAV",$C5
	.word	SLOAD_NFA	; LFA: previous name field in this vocabulary chain
SAVE:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: WRITE [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Writes screen n1 to the current device as specified by D# and F#.
; The written screen will be sent to cassette by default.
WRITE_NFA:
	.byte	$85,"WRIT",$C5
	.word	THDROP_NFA	; LFA: previous name field in this vocabulary chain
WRITE:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: CHKOUT [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: A KERNEL system call, which redirects character output to the
; channel specified as n1. The channel n1 must already be opened.
CHKOUT_NFA:
	.byte	$86,"CHKOU",$D4
	.word	SAVE_NFA	; LFA: previous name field in this vocabulary chain
CHKOUT:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: CLALL [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: A SYSTEM primitive, used to clear all channels, in the Commodore
; KERNEL to their default values. See the Commodore Programmers Reference
; Manual.
CLALL_NFA:
	.byte	$85,"CLAL",$CC
	.word	CHKOUT_NFA	; LFA: previous name field in this vocabulary chain
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: CHRIN [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- n1 )
; Manual: A KERNEL system call, which obtains a line of characters from the
; currently open character input channel, normally the keyboard. This routine
; waits for a line of input to be entered terminated by a carriage return;
; after a line of text has been entered, each call to CHRIN will return one
; character of the line entered. Note: CHRIN allows the use of the Commodore
; screen editor.
CHRIN_NFA:
	.byte	$85,"CHRI",$CE
	.word	CLALL_NFA	; LFA: previous name field in this vocabulary chain
CHRIN:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: BGROUND [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Selects background color for the screen, using the standard values
; for Commodore colors in the range 0 to 15.
BGROUND_NFA:
	.byte	$87,"BGROUN",$C4
	.word	WRITE_NFA	; LFA: previous name field in this vocabulary chain
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: BORDER [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Selects the screen BORDER color. N1 is a value between 0 and 15,
; for the colors as shown on page 139 of the Commodore 64 Users Guide.
BORDR_NFA:
	.byte	$86,"BORDE",$D2
	.word	BGROUND_NFA	; LFA: previous name field in this vocabulary chain
BORDR:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: UPORT [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- a1 )
; Manual: Returns the address of the user port In the Commodore 64 computer.
; Address a1 is the data port address.
UPORT_NFA:
	.byte	$85,"UPOR",$D4
	.word	BORDR_NFA	; LFA: previous name field in this vocabulary chain
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: DISK [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: This word selects the disk device for further mass storage
; operations by setting variable D# to the device specified by variable DR#,
; which is the actual drive number plus 8 (eight). This word is performed
; automatically by "FILE" operations. 121
DISK_NFA:
	.byte	$84,"DIS",$CB
	.word	UPORT_NFA	; LFA: previous name field in this vocabulary chain
DISK:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: CASSETTE [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: Selects the cassette for all further mass storage operations. This
; is the default mode, so it is not normally necessary to switch to CASSETTE.
; When a disk file has been opened and then closed, operation is
; automatically switched back to cassette.
CASSET_NFA:
	.byte	$88,"CASSETT",$C5
	.word	DISK_NFA	; LFA: previous name field in this vocabulary chain
CASSET:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: TALK [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: A KERNEL system call, which commands a device in the range of 0 to
; 31 to TALK on the serial bus. 146
TALK_NFA:
	.byte	$84,"TAL",$CB
	.word	CHRIN_NFA	; LFA: previous name field in this vocabulary chain
TALK:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: TKSA [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: A KERNEL system call, which sends byte value n1 in the range 0 to
; 31 as a secondary address command on the serial bus. This command is
; normally used after a TALK command to a device.
TKSA_NFA:
	.byte	$84,"TKS",$C1
	.word	TALK_NFA	; LFA: previous name field in this vocabulary chain
TKSA:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: 0.0 [SYSTEM].
; Manual stack: ( --- d1 )
; Manual: A space saving constant, which returns the double length (32-bit)
; value zero, used in several system calls.
DZERO_NFA:
	.byte	$83,"0.",$B0
	.word	TKSA_NFA	; LFA: previous name field in this vocabulary chain
DZERO:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	ZERO
	.word	ZERO
	.word	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: UNTLK [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Implementation: ( -- ) Call KERNAL UNTLK to end the serial TALK condition;
; discard returned register cells.
UNTLK_NFA:
	.byte	$85,"UNTL",$CB
	.word	DZERO_NFA	; LFA: previous name field in this vocabulary chain
UNTLK:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: UNLSN [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: A KERNEL system call, which tells all devices on the serial bus
; which were previously listening, to stop listening. Pronounced "unlisten."
UNLSN_NFA:
	.byte	$85,"UNLS",$CE
	.word	UNTLK_NFA	; LFA: previous name field in this vocabulary chain
UNLSN:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: ACPTR [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Implementation: ( -- byte ) Call KERNAL ACPTR and keep the returned A cell,
; dropping X/Y.
ACPTR_NFA:
	.byte	$85,"ACPT",$D2
	.word	UNLSN_NFA	; LFA: previous name field in this vocabulary chain
ACPTR:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: LISTEN [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Sends a command to cause device address n1 to listen for data on
; the serial bus.
LISTEN_NFA:
	.byte	$86,"LISTE",$CE
	.word	ACPTR_NFA	; LFA: previous name field in this vocabulary chain
LISTEN:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: CIOUT [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: A KERNEL system call, which sends a character n1 out of the serial
; bus. 116
CIOUT_NFA:
	.byte	$85,"CIOU",$D4
	.word	LISTEN_NFA	; LFA: previous name field in this vocabulary chain
CIOUT:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: SECOND [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: A KERNEL system call, which sends the secondary address on the
; serial bus, normally sent after the LISTEN command. See also SLSN and
; LISTEN.
SECOND_NFA:
	.byte	$86,"SECON",$C4
	.word	CIOUT_NFA	; LFA: previous name field in this vocabulary chain
SECOND:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: STYPE [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( a1/n1 --- )
; Manual: Sends n1 characters from address a1, out the serial bus. STYPE must
; be used after telling a device to listen. This is a low level primitive
; used by the system.
STYPE_NFA:
	.byte	$85,"STYP",$C5
	.word	SECOND_NFA	; LFA: previous name field in this vocabulary chain
STYPE:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: DTLK [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Sends a secondary address n l after telling the disk to talk.
; Pronounced "disk talk." 123
DTLK_NFA:
	.byte	$84,"DTL",$CB
	.word	STYPE_NFA	; LFA: previous name field in this vocabulary chain
DTLK:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: DLSN [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Sends a secondary address to the disk, after telling the disk to
; LISTEN. Pronounced "disk listen."
DLSN_NFA:
	.byte	$84,"DLS",$CE
	.word	DTLK_NFA	; LFA: previous name field in this vocabulary chain
DLSN:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: ?DERR [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: This word is very similar to ?D, but only prints a message to the
; terminal if there was a disk error. If no error has occurred, then
; operation continues after ?DERR. If an error condition was detected,
; execution is aborted.
QDERR_NFA:
	.byte	$85,"?DER",$D2
	.word	CASSET_NFA	; LFA: previous name field in this vocabulary chain
QDERR:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: ?D [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: This is a short word used to determine status of the disk, and to
; clear any error condition that might occur while disk operations are
; performed.
QDISK_NFA:
	.byte	$82,"?",$C4
	.word	QDERR_NFA	; LFA: previous name field in this vocabulary chain
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: --> [FORTH]; immediate (executes during compilation).
; Manual: Continues interpretation with the next disk screen. Pronounced
; "next-screen." 106
NEXT_SCREEN_NFA:
	.byte	$C3,"--",$BE
	.word	QDISK_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	ONE
	.word	BLK
	.word	PSTOR
	.word	ZERO
	.word	IN
	.word	STORE
	.word	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: <^> [FORTH].
; Manual stack: ( --- a1/n1 )
; Manual: A low level primitive compiled in-line when a string is built
; in-line in a colon-definition. This word returns the address of the string
; and the count of its length on the data stack. Not used from the keyboard.
ALIT_NFA:
	.byte	$83,"<^",$BE
	.word	NEXT_SCREEN_NFA	; LFA: previous name field in this vocabulary chain
ALIT:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	R
	.word	DUP
	.word	CAT
	.word	ONEP
	.word	RFROM
	.word	PLUS
	.word	TOR
	.word	COUNT
	.word	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: ^ [FORTH]; immediate (executes during compilation).
; Manual stack: ( --- a1/n1 )(text)
; Manual: This word allows text strings to be included into colondefinitions,
; in the form: : (name) ... A text string Here the string "text string" will
; be complied into definition (name), and when executed the address a1 of the
; string, and the length of the string n1 will be passed on the data stack to
; the words following, for further manipulation. This word can also be used
; outside of a definition, and will simply leave the address and count of the
; string of the text following on the data stack, with the string up above
; the PAD area. This word is often used with the system words DTYPE and
; STYPE, to send strings to the disk or serial bus. 153
UARROW_NFA:
	.byte	$C1,$DE
	.word	ALIT_NFA	; LFA: previous name field in this vocabulary chain
UARROW:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	STATE
	.word	AT
	.word	ZBRAN,$18	; Pop flag; if zero branch to $A483 (offset +24 from operand cell)
	.word	COMP
	.word	ALIT	; Inline CFA operand consumed by COMPILE
	.word	LIT,$5E		; '^'
	.word	WORD
	.word	HERE
	.word	CAT
	.word	ONEP
	.word	ALLOT
	.word	BRAN,$1A	; Jump to $A49B (offset +26 from operand cell)
	.word	LIT,$5E		; '^'
	.word	WORD
	.word	HERE
	.word	DUP
	.word	CAT
	.word	ONEP
	.word	PAD
	.word	SWAP
	.word	CMOVE
	.word	PAD
	.word	COUNT
	.word	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: DRIVE [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Selects drive n1 as the currently active disk drive, by setting
; user variable DR# to the drive number plus 8. See also DRIVE? and DR#.
DRIVE_NFA:
	.byte	$85,"DRIV",$C5
	.word	UARROW_NFA	; LFA: previous name field in this vocabulary chain
DRIVE:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: DRIVE? [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- n1 )
; Manual: Returns the drive number of the currently active disk drive;
; defaults to device 8 drive 0. See also DRIVE and DR#.
DRIVE_QUERY_NFA:
	.byte	$86,"DRIVE",$BF
	.word	DRIVE_NFA	; LFA: previous name field in this vocabulary chain
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: DTYPE [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1/a1/n2 --- )
; Manual: Sends the character string at address a1, for length n2 to channel
; n1 in the serial bus. Pronounced "disk type."
DTYPE_NFA:
	.byte	$85,"DTYP",$C5
	.word	DLSN_NFA	; LFA: previous name field in this vocabulary chain
DTYPE:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: /CMD [FORTH]; immediate (executes during compilation).
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- t )
; Manual: Sends the text string 't' to channel n1 on the serial bus. This is
; a lower level word than CMD, which always sends a command string to the
; disk drive.
SCMD_NFA:
	.byte	$C4,"/CM",$C4
	.word	DRIVE_QUERY_NFA	; LFA: previous name field in this vocabulary chain
SCMD:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: CMD [FORTH]; immediate (executes during compilation).
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- t )
; Manual: A utility word, used to send command lines to the disk. The
; sequence "CMD I ( return )" would cause the disk to be initialized. This
; word can be used in a definition, or on a line with multiple commands. But
; when this is done, the command string must be terminated with an up arrow
; "^" as shown in the following example: : INIT CMD ^ ; This definition
; initializes the current disk drive, and must not be used while a disk file
; is open.
CMD_NFA:
	.byte	$C3,"CM",$C4
	.word	SCMD_NFA	; LFA: previous name field in this vocabulary chain
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: (FILE) [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- t )
; Manual: This is a low level word used by FILE, which opens the file
; specified by text 't'. (FILE) does not empty the screens out of memory
; before opening the new file. This word is used mostly when copying screens
; from cassette to disk, or when copying screens from one disk file to
; another.
PFILE_NFA:
	.byte	$86,"(FILE",$A9
	.word	CMD_NFA	; LFA: previous name field in this vocabulary chain
PFILE:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: ^FILE [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( a1/n1 --- )
; Manual: This word opens the file name string at address a1, for character
; length n1, after first closing any file that is currently open. The text
; string should not be placed at HERE, because HERE is used for other
; processing. The variable FN is recommended as the optimum location for file
; name storage.
UFILE_NFA:
	.byte	$85,"^FIL",$C5
	.word	PFILE_NFA	; LFA: previous name field in this vocabulary chain
UFILE:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: (^FILE) [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( a1/n1 --- )
; Manual: Similar to (FILE), but requires an address a1 of the text string
; for the file to open, and n1 the length of the name. The file is opened,
; but memory Is not cleared before opening the file. See also ^FILE (FILE)
; FILE. 104
PUFIL_NFA:
	.byte	$87,"(^FILE",$A9
	.word	UFILE_NFA	; LFA: previous name field in this vocabulary chain
PUFIL:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: FILE [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- t )
; Manual: Closes any file currently open, and opens the file specified by
; text 't' on the currently specified disk drive. Any updated screen in
; memory will be flushed to the previously open file before it is closed. A
; user variable called BMAX contains the highest numbered screen that can be
; accessed. If you wish to manipulate a disk file larger than 16k bytes, you
; will have to change the value of BMAX to a larger number. The largest
; single file that may be created is 90k bytes. This is due to a limitation
; of the Commodore DOS.
FILE_NFA:
	.byte	$84,"FIL",$C5
	.word	PUFIL_NFA	; LFA: previous name field in this vocabulary chain
FILE:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: (FCLOSE) [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: This is a low level word used by FCLOSE, which closes the currently
; open disk file without emptying the memory buffer contents. Useful mostly
; for transferring screens from cassette to disk, and when copying screens
; from one file to another with the utility FCOPY.
PFCLOS_NFA:
	.byte	$88,"(FCLOSE",$A9
	.word	FILE_NFA	; LFA: previous name field in this vocabulary chain
PFCLOS:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: FCLOSE [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: Closes the current disk file and clears all screen buffers to
; blanks. If you need to close a file without clearing the screen buffers,
; use (FCLOSE). 127
FCLOSE_NFA:
	.byte	$86,"FCLOS",$C5
	.word	PFCLOS_NFA	; LFA: previous name field in this vocabulary chain
FCLOSE:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: POS [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Sets the position of the relative fife pointer to record n1.
; 64FORTH uses 129 byte records.
POS_NFA:
	.byte	$83,"PO",$D3
	.word	DTYPE_NFA	; LFA: previous name field in this vocabulary chain
POS:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: SLSN [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: A system primitive, which commands the disk drive to listen with a
; secondary address of n1. Pronounced "secondary listen."
SLSN_NFA:
	.byte	$84,"SLS",$CE
	.word	POS_NFA	; LFA: previous name field in this vocabulary chain
SLSN:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: RECWRITE [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( a1/n1 --- )
; Manual: Writes a record to the currently open disk file, from address a1,
; for length n1 bytes, and terminates the write with a carriage return (13
; decimal). Caution is recommended in the use of this word; normally a POS is
; performed before a RECWRITE. n1 is always 128 in 64FORTH.
RECWRT_NFA:
	.byte	$88,"RECWRIT",$C5
	.word	SLSN_NFA	; LFA: previous name field in this vocabulary chain
RECWRT:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: RECREAD [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( a1 --- a2 )
; Manual: Reads a record from the currently open disk file, into address a1,
; and returns address a2, which is address a1 plus length of the normal read.
; Caution is recommended in the use of this word. Normally a POS is performed
; before a RECREAD.
RECREA_NFA:
	.byte	$87,"RECREA",$C4
	.word	RECWRT_NFA	; LFA: previous name field in this vocabulary chain
RECREA:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: BLKWRITE [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( a1/n1 --- )
; Manual: This is a disk block primitive, which writes block n1 to disk from
; address a1, to the currently open RELATIVE disk file. A disk error will be
; reported the first time a write is performed to a previously non-existent
; screen. However, this error should be ignored if it is a non-existent
; record error.
BLKWRT_NFA:
	.byte	$88,"BLKWRIT",$C5
	.word	RECREA_NFA	; LFA: previous name field in this vocabulary chain
BLKWRT:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: BLKREAD [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( a1/n1 --- )
; Manual: The disk storage primitive which reads block n1 into address a1
; from the currently open RELATIVE file. A disk error will be reported when
; reading or writing the first time to a newly created screen in a disk file.
; This error should be ignored, as it is a peculiarity of the Commodore Disk
; Operating System.
BLKRD_NFA:
	.byte	$87,"BLKREA",$C4
	.word	BLKWRT_NFA	; LFA: previous name field in this vocabulary chain
BLKRD:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: R/W [SYSTEM].
; Manual stack: ( a blk f --- )
; Manual: The fig-FORTH standard disk read-write linkage. A (address)
; specifies the source or destination block buffer; blk is the sequential
; number of the referenced block; and f 139 is a flag for f=0 write and f=1
; read. R/W determines the location on mass storage, performs the read-write
; and performs any error checking. This is a vectored word.
RSLW_NFA:
	.byte	$83,"R/",$D7
	.word	BLKRD_NFA	; LFA: previous name field in this vocabulary chain
RSLW:
	.word	DOVEC	; CFA: vectored word; dispatch through UP+$32+offset
	.byte	22	; Vector byte offset 22 from I/O (UP+$32)

PRSLW:
	.word	NO_C64	; C64 storage backend unavailable

; ---------------------------------------------------------------------------
; Dictionary: UPDATE [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual: Marks the most recently referenced block as altered. The block will
; subsequently be transferred automatically to disk should its buffer be
; required for storage of a different block.
UPDATE_NFA:
	.byte	$86,"UPDAT",$C5
	.word	FCLOSE_NFA	; LFA: previous name field in this vocabulary chain
UPDATE:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: EMPTY-BUFFERS [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual: Mark all block-buffers as empty, not necessarily affecting the
; contents. Updated blocks are not written to the disk. This is also an
; initialization procedure before first use of the disk.
MTBUF_NFA:
	.byte	$8D,"EMPTY-BUFFER",$D3
	.word	UPDATE_NFA	; LFA: previous name field in this vocabulary chain
MTBUF:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: >RAM [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: This is a system primitive, which uncovers the ram under the KERNEL
; and I/O from $D000 to $FFFF. Virtual buffer operations can then be
; performed to this area. This word is only used by the system, and MUST NOT
; be used from the keyboard, since NO I/O can be performed while the 110
; KERNEL is switched out. The logical reverse of this word is RAM>, which
; restores the KERNEL and I/O to the memory map.
TORAM_NFA:
	.byte	$84,">RA",$CD
	.word	RSLW_NFA	; LFA: previous name field in this vocabulary chain
; Banking entry: write $7F to CIA1IC to disable its IRQ sources, then $34 to
; the 6510 port via ONE C!. This exposes RAM under ROM/I/O. The copied
; interpreter in underlying RAM makes continued execution possible.
TORAM:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: RAM> [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: Selects the KERNEL and I/O back into the system, pronounced RAM
; FROM. See also >RAM.
FRAM_NFA:
	.byte	$84,"RAM",$BE
	.word	TORAM_NFA	; LFA: previous name field in this vocabulary chain
; Banking exit: write $37 to the 6510 port to restore cartridge/KERNAL/I/O
; mapping, then enable CIA 1 timer A IRQs with $81. This restores fixed
; defaults, not a previously saved bank/IRQ mask. The original $A765 location is the documented
; soft-load patch byte.
FRAM:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: >BUF [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( a1/n1 --- )
; Manual: This is one of the buffer deblocking primitives. Its function is to
; send the 1k block of data at address a1, to the screen buffer specified by
; n1, in upper memory. A modulus operation is performed on the values n1, to
; determine into which buffer the data is to be placed. There are currently
; 16 virtual buffers in high memory, and a modulus 16 operations is performed
; to determine the buffer location for use. If the buffer already contains
; data from a different block (as in block 1 and block 17, which both modulus
; to screen buffer 1), then the contents of the old screen 1 in this case
; must be written out to disk before the new screen, 17, can be moved to the
; buffer. This operation is done by GBLOCK, and must be performed before >BUF
; is executed. See also BUF> GBLOCK.
TOBUF_NFA:
	.byte	$84,">BU",$C6
	.word	FRAM_NFA	; LFA: previous name field in this vocabulary chain
TOBUF:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: BUF> [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( a1/n1 --- )
; Manual: Moves the data for screen n1 from the virtual screen buffer to
; address a1, used by GBLOCK to perform SCREEN DEBLOCKING.
FBUF_NFA:
	.byte	$84,"BUF",$BE
	.word	TOBUF_NFA	; LFA: previous name field in this vocabulary chain
FBUF:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: BUFADD [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- a1 )
; Manual: This word calculates the address of the buffer which should hold
; the screen specified as n1, and returns the buffer address as a1.
BUFAD_NFA:
	.byte	$86,"BUFAD",$C4
	.word	FBUF_NFA	; LFA: previous name field in this vocabulary chain
; Backing slot address = $C000 + 1024*((max((block & $7FFF)-1,0)) & 15).
; Strip the dirty flag before indexing. Sixteen slots wrap cyclically; PTRADD
; indexes the parallel 16-cell tag table.
BUFAD:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: PTRADD [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- a1 )
; Manual: A system primitive, which accepts the value n1, a screen and
; returns the address a1 which is the address inside of the BLKTBL array
; which specifies which screens are currently in memory. 138
PTRADD_NFA:
	.byte	$86,"PTRAD",$C4
	.word	BUFAD_NFA	; LFA: previous name field in this vocabulary chain
PTRADD:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: CURBLK [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- n1 )
; Manual: Returns the non-updated screen number of the screen most recently
; addressed with BLOCK. Used by the virtual disk interface.
CURBLK_NFA:
	.byte	$86,"CURBL",$CB
	.word	PTRADD_NFA	; LFA: previous name field in this vocabulary chain
CURBLK:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: COMBUF [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- a1 )
; Manual: This is the buffer used to send and receive screen data to and from
; the disk drive. This buffer is 1024 bytes long, and is in NON-PAGED memory.
COMBUF_NFA:
	.byte	$86,"COMBU",$C6
	.word	CURBLK_NFA	; LFA: previous name field in this vocabulary chain
COMBUF:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: BLKTBL [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- a1 )
; Manual: This is a system array variable, which points to the beginning of
; the table indicating the screens that are currently in the memory buffers.
; This array is 32 decimal bytes long.
BLKTBL_NFA:
	.byte	$86,"BLKTB",$CC
	.word	COMBUF_NFA	; LFA: previous name field in this vocabulary chain
BLKTBL:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: FLUSH [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: This system uses the intelligent version of flush. After a screen
; is written to disk, it is left in memory also, to prevent a screen reread,
; although its UPDATE bit is cleared.
FLUSH_NFA:
	.byte	$85,"FLUS",$C8
	.word	MTBUF_NFA	; LFA: previous name field in this vocabulary chain
; Write back dirty active-screen data to its backing slot, then scan all
; sixteen slot tags. Bit 15 marks modified data; GBLOCK writes the
; corresponding block through R/W and the tag is cleared afterward.
FLUSH:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: GBLOCK [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: This is the main disk interface word in this version of FORTH. It
; performs the screen buffer deblocking, and reads the requested screen n1
; into the user disk buffer from disk of the virtual screen buffers in high
; memory. It also takes care of writing any needed screens to disk as
; required.
GBLOCK_NFA:
	.byte	$86,"GBLOC",$CB
	.word	BLKTBL_NFA	; LFA: previous name field in this vocabulary chain
; Select the active screen: if its block differs, preserve the old buffer,
; consult the direct-mapped slot tag, and either copy the cached slot or read
; from the device. Maintain the active header and trailing zero cell.
GBLOCK:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: FORTH [FORTH]; immediate (executes during compilation).
; Implementation: Select the FORTH dictionary through DOVOC. The writable
; instance is copied to $0840 at startup.
; RAM VOCABULARY TEMPLATE. EMPTY copies this region to $0840. DODOE/DOVOC
; select a vocabulary; their latest-name and vocabulary-link cells must
; reside in writable RAM. Literal $0848 references execute the RAM FORTH
; copy, not this ROM template.
FORTH_NFA:
	.byte	$C5,"FORT",$C8
	.word	NOOP_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOVOC
	.word	$A081
FORTH_LATEST:
	.word	FORTH_BUILTIN_LATEST
	.word	0

; ---------------------------------------------------------------------------
; Dictionary: SYSTEM [FORTH]; immediate (executes during compilation).
; Implementation: Select the SYSTEM dictionary through DOVOC. Startup copies
; this vocabulary descriptor into RAM.
SYSTEM_NFA:
	.byte	$C6,"SYSTE",$CD
	.word	$840	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOVOC
	.word	$A081
SYSTEM_LATEST:
	; .word	SCRNQ_NFA
	.word	MASKQ_NFA
	.word	$850

; ---------------------------------------------------------------------------
; Dictionary: ASSEMBLER [FORTH]; immediate (executes during compilation).
; Manual: Makes ASSEMBLER the context vocabulary. It will be searched first
; when the input stream is interpreted.
ASSEMBLER_NFA:
	.byte	$C9,"ASSEMBLE",$D2
	.word	$852	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOVOC
	.word	$A081
ASSEMBLER_LATEST:
	.word	END_CODE_NFA
	.word	$863

; ---------------------------------------------------------------------------
; Dictionary: EDITOR [FORTH]; immediate (executes during compilation).
; Implementation: Select the EDITOR dictionary through DOVOC. EDIT also
; installs the editor key-capture table.
EDITOR_NFA:
	.byte	$C6,"EDITO",$D2
	.word	$865	; LFA: previous name field in this vocabulary chain
EDITOR:
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOVOC
	.word	$A081
EDITOR_LATEST:
	.word	VV_NFA
	.word	$879

VOCABULARY_LATEST_TABLE:
	.word	FORTH_LATEST		; TOP FORTH WORD
	.word	SYSTEM_LATEST		; TOP SYSTEM WORD
	.word	ASSEMBLER_LATEST		; TOP ASSEMBLER WORD
	.word	EDITOR_LATEST		; TOP EDITOR WORD

; ---------------------------------------------------------------------------
; Dictionary: NOOP [FORTH].
; Implementation: ( -- ) Empty colon definition; immediately returns to its
; caller.
NOOP_NFA:
	.byte	$84,"NOO",$D0
	.word	FLUSH_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: DLOAD [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- t )
; Manual: Allows you to load your pre-compiled FORTH dictionary from cassette
; or disk. Used as follows: DLOAD <t> <RETURN> will load a pre-compiled
; dictionary from the cassette file named <t>. To load from disk, preceed the
; word DLOAD with the word DISK as follows: DISK DLOAD <t> <RETURN> Any disk
; file currently open should be closed before performing DLOAD.
DLOAD_NFA:
	.byte	$85,"DLOA",$C4
	.word	$87B	; LFA: previous name field in this vocabulary chain
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: DSAVE [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- t )
; Manual: Saves your compiled dictionary to cassette or disk. Used as
; follows: DSAVE <t> <RETURN> will save a pre-compiled dictionary from the
; cassette file named <t>. To save from disk, preceed the word DSAVE with the
; word DISK as follows: DISK DSAVE <t> <RETURN> Any disk file currently open
; should be closed before performing DSAVE.
DSAVE_NFA:
	.byte	$85,"DSAV",$C5
	.word	DLOAD_NFA	; LFA: previous name field in this vocabulary chain
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: FLOAD [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- <t> )
; Manual: Opens file <t> on current disk drive and loads screen 1. Screen 1
; is expected to load the rest of the file.
FLOAD_NFA:
	.byte	$85,"FLOA",$C4
	.word	DSAVE_NFA	; LFA: previous name field in this vocabulary chain
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: .FREE [FORTH].
; IMNOTWOPR: reports remaining dictionary space, excluding parser workspace.
; Implementation: ( -- ) Print EM @ minus HERE, the remaining dictionary
; space.
DOTFREE_NFA:
	.byte	$85,".FRE",$C5
	.word	FLOAD_NFA	; LFA: previous name field in this vocabulary chain
    .word DOCOL
    .word EM,AT,HERE,SUBB
    .word LIT,DICT_WORKSPACE,SUBB,DOT,SEMIS

; ---------------------------------------------------------------------------
; Dictionary: TRIAD [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( scr --- )
; Manual: Displays on the selected output device the three screens which
; include that numbered screen, beginning with a screen evenly divisible by
; three. Output is suitable for source text records. The screens to be
; printed must already be in memory.
TRIAD_NFA:
	.byte	$85
	.byte	"TRIA",$C4
	.word	DOTFREE_NFA	; LFA: previous name field in this vocabulary chain
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: CLOSE [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: A KERNEL system call, which closes the channel n1 specified to the
; Commodore operating system.
CLOSE_NFA:
	.byte	$85,"CLOS",$C5
	.word	GBLOCK_NFA	; LFA: previous name field in this vocabulary chain
CLOSE:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: PROFF [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: Restores character output to the video screen, and turns off the
; serial bus printer channel.
PROFF_NFA:
	.byte	$85,"PROF",$C6
	.word	CLOSE_NFA	; LFA: previous name field in this vocabulary chain
PROFF:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: CHKIN [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: A KERNEL system call, which redirects character input to the
; channel specified as n1. The channel n1 must already be open.
CHKIN_NFA:
	.byte	$85,"CHKI",$CE
	.word	PROFF_NFA	; LFA: previous name field in this vocabulary chain
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: PRON [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: Opens the serial bus printer channel, and directs all character
; output to that channel. If no printer is connected, the computer may HANG.
PRON_NFA:
	.byte	$84,"PRO",$CE
	.word	CHKIN_NFA	; LFA: previous name field in this vocabulary chain
PRON:
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: TRY [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Implementation: ( -- ) Interpret the screen currently held in SCR by
; executing LOAD.
TRY_NFA:
	.byte	$83,"TR",$D9
	.word	TRIAD_NFA	; LFA: previous name field in this vocabulary chain
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: PRINT [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- (text) )
; Manual: Sends all character output from the following command line as
; specified by (text) to the serial bus printer.
PRINT_NFA:
	.byte	$85,"PRIN",$D4
	.word	TRY_NFA	; LFA: previous name field in this vocabulary chain
	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: FORGET [FORTH].
; Manual: Executed In the form: FORGET cccc Deletes definition named cccc
; from the dictionary with all entries physically following it. In 64FORTH an
; error message will occur If the CURRENT and CONTEXT vocabularies are not
; currently the same. See FENCE.
FORG_NFA:
	.byte	$86,"FORGE",$D4
	.word	PRINT_NFA	; LFA: previous name field in this vocabulary chain
FORG:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	TICK
	.word	NFA
	.word	DUP
	.word	FENCE
	.word	AT
	.word	LESS
	.word	LIT	; Push following inline 16-bit cell
	.word	$15	; Inline literal value, not a call
	.word	QERR
	.word	TOR
	.word	VOCL
	.word	AT
	.word	R
	.word	OVER
	.word	LESS
	.word	ZBRAN,$C	; Pop flag; if zero branch to $AB98 (offset +12 from operand cell)
	.word	RAMFTH		; FORTH
	.word	DEFIN
	.word	AT
	.word	BRAN,$FFEE	; Jump to $AB84 (offset -18 from operand cell)
	.word	DUP
	.word	VOCL
	.word	STORE
	.word	DUP
	.word	LIT,4
	.word	SUBB
	.word	PFA
	.word	LFA
	.word	AT
	.word	DUP
	.word	R
	.word	LESS
	.word	ZBRAN,$FFF2	; Pop flag; if zero branch to $ABA6 (offset -14 from operand cell)
	.word	OVER
	.word	TWO
	.word	SUBB
	.word	STORE
	.word	AT
	.word	QDUP
	.word	ZEQU
	.word	ZBRAN,$FFD8	; Pop flag; if zero branch to $AB9E (offset -40 from operand cell)
	.word	RFROM
	.word	DP
	.word	STORE
	.word	SEMIS	; Return to caller thread

; ===========================================================================
; FORTH-HOSTED 6502 ASSEMBLER
; ===========================================================================

; ---------------------------------------------------------------------------
; Dictionary: N [ASSEMBLER].
; Manual stack: ( --- a1 ) (assembling)
; Manual: Used in a code-definition in the form: N1 - sta, or n2 = )Y adc, A
; constant which leaves the address of a 9 byte workspace in z-page. Within a
; single code definition, free use may be made over the range N-1 through
; N-7.
ASM_N_NFA:
	.byte	$81,$CE
	.word	$84C	; LFA: previous name field in this vocabulary chain
	.word	DOCON	; CFA: constant; push the following 16-bit value
	.word	N

; ---------------------------------------------------------------------------
; Dictionary: IP [ASSEMBLER].
; Manual stack: ( --- a1 ) (assembling)
; Manual: Used in a code definition in the form: IP sta, or IP) Y lda, A
; constant which leaves the address of the pointer to the next FORTH
; execution address in a colon-definition to be interpreted at assembly time.
; At run-time, NEXT moves IP ahead within a colon-definition. Therefore, IP
; points just after the execution address being interpreted. If an in-line
; data structure has been compiled (i.e. a character string), indexing ahead
; by IP can access this data: IP sta, or [P) Y lda, Loads the third byte
; ahead in the colon-definition being interpreted.
ASM_IP_NFA:
	.byte	$82,"I",$D0
	.word	ASM_N_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCON	; CFA: constant; push the following 16-bit value
	.word	IP

; ---------------------------------------------------------------------------
; Dictionary: W [ASSEMBLER].
; Manual stack: ( --- a1 ) (assembling)
; Manual: Used in a code definition in the form: W 1+ sta, or W 1 - jmp, or
; W) Y adc, A constant which leaves at assembly time the address of the
; pointer to the code field (execution address) of the FORTH dictionary word
; being executed. Indexing relative to W can yield any byte in the definition
; parameter field, for example: 3 # ldy, fetches the first byte of the
; parameter field.
ASM_W_NFA:
	.byte	$81,$D7
	.word	ASM_IP_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCON	; CFA: constant; push the following 16-bit value
	.word	W

; ---------------------------------------------------------------------------
; Dictionary: UP [ASSEMBLER].
; Manual stack: ( --- a1 ) (assembling)
; Manual: Used in a code definition in the form: UP lda, or UP) Y sta, A
; constant leaving at assembly time the address of the pointer to the base of
; the user area. For example: HEX 12 # ldy, UP) Y, lda Loads the low byte of
; the sixth user variable, DP.
ASM_UP_NFA:
	.byte	$82,"U",$D0
	.word	ASM_W_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCON	; CFA: constant; push the following 16-bit value
	.word	UP

; ---------------------------------------------------------------------------
; Dictionary: XSAVE [ASSEMBLER].
; Manual stack: ( --- a1 ) (assembling)
; Manual: Used in a code definition in the form: XSAVE stx, or XSAVE ldx, 152
; A constant which leaves the address at assembly time of a temporary buffer
; for saving the X register. Since the X register indexes to the data stack
; in z-page, it must be saved and restored when used for other purposes.
ASM_XSAVE_NFA:
	.byte	$85,"XSAV",$C5
	.word	ASM_UP_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCON	; CFA: constant; push the following 16-bit value
	.word	XSAVE

; ---------------------------------------------------------------------------
; Dictionary: NEXTMP [ASSEMBLER].
; Implementation: ( -- addr ) Assembler constant giving the NXTMP zero-page
; address used for indirect dispatch.
ASM_NEXTMP_NFA:
	.byte	$86,"NEXTM",$D0
	.word	ASM_XSAVE_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCON	; CFA: constant; push the following 16-bit value
	.word	NXTMP

; ---------------------------------------------------------------------------
; Dictionary: POP [ASSEMBLER].
; Manual stack: ( --- a1 ) (assembling)
; Manual: ( n1 --- ) (run-time) A constant which leaves (during assembly) the
; machine address of the return point which, at run-time, will pop a 16 bit
; value from the data stack and continue interpretation.
ASM_POP_NFA:
	.byte	$83,"PO",$D0
	.word	ASM_NEXTMP_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCON	; CFA: constant; push the following 16-bit value
	.word	POP

; ---------------------------------------------------------------------------
; Dictionary: POPTWO [ASSEMBLER].
; Manual stack: ( --- a1 ) (assembling)
; Manual: ( n1/n2 --- ) (run-time) A constant which leaves (during assembly)
; the machine address of the return point, which, at run-time, will pop two
; 16-bit values from the data stack and continue interpretation.
ASM_POPTWO_NFA:
	.byte	$86,"POPTW",$CF
	.word	ASM_POP_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCON	; CFA: constant; push the following 16-bit value
	.word	POPTWO

; ---------------------------------------------------------------------------
; Dictionary: PUT [ASSEMBLER].
; Manual stack: ( --- a1 ) (assembling)
; Manual: ( n1 --- n2 ) (run-time) A constant which leaves (during assembly)
; the machine address of the return point which, at run-time, will write the
; accumulator (as high byte) and the bottom machine stack byte (as low byte)
; over the existing data stack 16-bit value n1.
ASM_PUT_NFA:
	.byte	$83,"PU",$D4
	.word	ASM_POPTWO_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCON	; CFA: constant; push the following 16-bit value
	.word	PUT

; ---------------------------------------------------------------------------
; Dictionary: PUSH [ASSEMBLER].
; Manual stack: ( --- a1 ) (assembling)
; Manual: ( --- n1 ) (leaving) A constant which leaves (during assembly) the
; machine address of the return point which, at run-time, will add the
; accumulator (as high byte) and the bottom machine stack byte (as low byte)
; to the data stack.
ASM_PUSH_NFA:
	.byte	$84,"PUS",$C8
	.word	ASM_PUT_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCON	; CFA: constant; push the following 16-bit value
	.word	PUSH

; ---------------------------------------------------------------------------
; Dictionary: NEXT [ASSEMBLER].
; Manual stack: ( --- a1 ) (assembling)
; Manual: A constant which leaves the machine address of the FORTH address
; interpreter. All code definitions must return execution to NEXT, or code
; that returns to NEXT (that is, PUSH, PUT, POP, POPTWO).
ASM_NEXT_NFA:
	.byte	$84,"NEX",$D4
	.word	ASM_PUSH_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCON	; CFA: constant; push the following 16-bit value
	.word	NEXT

; ---------------------------------------------------------------------------
; Dictionary: SETUP [ASSEMBLER].
; Implementation: ( -- addr ) Assembler constant giving the address of the
; native SETUP helper. See the native entry for A/Y inputs and clobbered
; scratch space.
ASM_SETUP_NFA:
	.byte	$85,"SETU",$D0
	.word	ASM_NEXT_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCON	; CFA: constant; push the following 16-bit value
	.word	SETUP

; ---------------------------------------------------------------------------
; Dictionary: INDEX [ASSEMBLER].
; Manual stack: ( --- a1 ) (assembling)
; Manual: An array used within the assembler, which holds bit patterns of
; allowable addressing modes.
INDEX_NFA:
	.byte	$85,"INDE",$D8
	.word	ASM_SETUP_NFA	; LFA: previous name field in this vocabulary chain
; Assembler opcode adjustment table: indexed by addressing-mode selection.
; $80 marks an unavailable combination. M/CPU combines these offsets with an
; instruction family base and validates mode masks before emitting bytes.
INDEX:
	.word	DOVAR	; CFA: variable; push the parameter-field address
	.byte	$09,$09,$05,$15,$15,$01,$11,$80
	.byte	$09,$80,$0D,$1D,$19,$80,$80,$80
	.byte	$80,$00,$04,$14,$14,$80,$80,$80
	.byte	$80,$80,$0C,$1C,$1C,$80,$80,$2C

; ---------------------------------------------------------------------------
; Dictionary: MODE [ASSEMBLER].
; Manual stack: ( --- a1 )
; Manual: A user variable used within the assembler, which holds a flag
; indicating the addressing mode of the op-code being generated. 135
MODE_NFA:
	.byte	$84,"MOD",$C5
	.word	INDEX_NFA	; LFA: previous name field in this vocabulary chain
; LISTING/MANUAL DIFFERENCE: the bytes here are $02,$02, and DOUSE reads only
; the first. This ROM therefore returns UP+$02 ($0942), whereas the manual
; user-variable table lists MODE at $0A0A (offset $CA). The original bytes
; are preserved.
MODE:
	.word	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.byte	$02	; User offset $0002; initial address $0942
	.byte	$02

; ---------------------------------------------------------------------------
; Dictionary: .A [ASSEMBLER].
; Implementation: Assembler mode selector: set MODE to 0 for accumulator
; addressing.
ASM_ACCUMULATOR_NFA:
	.byte	$82,".",$C1
	.word	MODE_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	ZERO
	.word	MODE
	.word	STORE
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: # [ASSEMBLER].
; Manual stack: ( --- )
; Manual: Specify 'immediate' addressing mode for the next op-code generated.
ASM_IMMEDIATE_NFA:
	.byte	$81,$A3
	.word	ASM_ACCUMULATOR_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	ONE
	.word	MODE
	.word	STORE
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: MEM [ASSEMBLER].
; Manual: Used with the assembler to set MODE to the default value for direct
; memory addressing, z-page.
MEM_NFA:
	.byte	$83,"ME",$CD
	.word	ASM_IMMEDIATE_NFA	; LFA: previous name field in this vocabulary chain
MEM:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	TWO
	.word	MODE
	.word	STORE
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ,X [ASSEMBLER].
; Manual stack: ( --- )
; Manual: Specify 'indexed X' addressing mode for the next op-code generated.
ASM_INDEXED_X_NFA:
	.byte	$82,",",$D8
	.word	MEM_NFA	; LFA: previous name field in this vocabulary chain
ASM_INDEXED_X:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	THREE
	.word	MODE
	.word	STORE
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ,Y [ASSEMBLER].
; Implementation: Assembler mode selector: set MODE to 4 for Y-indexed memory
; addressing.
ASM_INDEXED_Y_NFA:
	.byte	$82,",",$D9
	.word	ASM_INDEXED_X_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	LIT,4
	.word	MODE
	.word	STORE
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: X) [ASSEMBLER].
; Manual: Specify 'indexed indirect X' addressing mode for the next op-code
; generated.
ASM_INDEXED_INDIRECT_X_NFA:
	.byte	$82,"X",$A9
	.word	ASM_INDEXED_Y_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	LIT,5
	.word	MODE
	.word	STORE
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: )Y [ASSEMBLER].
; Manual stack: ( --- )
; Manual: Specify 'indirect indexed Y' addressing mode for the next op-code
; generated.
ASM_INDIRECT_INDEXED_Y_NFA:
	.byte	$82,")",$D9
	.word	ASM_INDEXED_INDIRECT_X_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	LIT,6
	.word	MODE
	.word	STORE
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ) [ASSEMBLER].
; Manual stack: ( --- )
; Manual: Specify 'indirect' addressing for the next op-code generated. Used
; only on the jmp instructions.
ASM_INDIRECT_NFA:
	.byte	$81,$A9
	.word	ASM_INDIRECT_INDEXED_Y_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	LIT,$F
	.word	MODE
	.word	STORE
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: BOT [ASSEMBLER].
; Manual stack: ( --- n1 )
; Manual: Used during code assembly in the form: BOT lda, or BOT X) sta,
; Addresses the bottom of the data stack (containing the low byte) by
; selecting the X mode and leaving n1=0 at assembly time. This value of n1
; may be modified to another byte offset Into the data stack. Must be
; followed by a multi-mode op-code mnemonic.
ASM_BOT_NFA:
	.byte	$83,"BO",$D4
	.word	ASM_INDIRECT_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	ASM_INDEXED_X
	.word	ZERO
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: sec [ASSEMBLER].
; Manual stack: ( --- n1 ) (assembling)
; Manual: Identical to BOT, except that n1=2. Addressing the low byte of the
; second 16-bit data stack value (third byte on the low data stack).
ASM_SECOND_CELL_NFA:
	.byte	$83,"SE",$C3
	.word	ASM_BOT_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	ASM_INDEXED_X
	.word	TWO
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: RP) [ASSEMBLER].
; Manual stack: ( --- n1 ) (assembly-time)
; Manual: Used in the code definition in the form: RP) lda, or RP) 3 + sta,
; Addresses the bottom byte of the return stack (containing the low byte) by
; selecting X mode and leaving n1=$0101. N1 may be modified to another byte
; offset. Before operating on the return stack the X register must be saved
; in XSAVE and tsx, must be executed; before returning to NEXT, the X
; register must be restored.
ASM_RETURN_STACK_NFA:
	.byte	$83,"RP",$A9
	.word	ASM_SECOND_CELL_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	ASM_INDEXED_X
	.word	LIT,$101
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: UPMODE [ASSEMBLER].
; Implementation: Assembler helper: upgrade the mode when needed, construct
; its mode-mask bit and report whether the instruction descriptor permits it.
UPMODE_NFA:
	.byte	$86,"UPMOD",$C5
	.word	ASM_RETURN_STACK_NFA	; LFA: previous name field in this vocabulary chain
UPMODE:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	ZBRAN,$1A	; Pop flag; if zero branch to $AD55 (offset +26 from operand cell)
	.word	MODE
	.word	AT
	.word	LIT,8
	.word	ANDD
	.word	ZEQU
	.word	ZBRAN,$A	; Pop flag; if zero branch to $AD55 (offset +10 from operand cell)
	.word	LIT,8
	.word	MODE
	.word	PSTOR
	.word	ONE
	.word	MODE
	.word	AT
	.word	LIT,$F
	.word	ANDD
	.word	QDUP
	.word	ZBRAN,$E	; Pop flag; if zero branch to $AD73 (offset +14 from operand cell)
	.word	ZERO
	.word	PDO
	.word	DUP
	.word	PLUS
	.word	PLOOP,$FFFA	; Increment loop index; if continuing branch to $AD6B (offset -6 from operand cell)
	.word	OVER
	.word	ONEP
	.word	AT
	.word	ANDD
	.word	ZEQU
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: CPU [ASSEMBLER].
; Manual stack: ( n1 --- ) (compiling assembler)
; Manual: An assembler defining word used to create assembler mnemonics that
; have only one addressing mode: EA CPU NOP, CPU creates the word NOP, with
; its op-code EA as a parameter. When NOP is later executed, it assembles EA
; as a one byte op-code. 118
ASM_CPU_NFA:
	.byte	$83,"CP",$D5
	.word	UPMODE_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	BUILD
	.word	CCOM
	.word	DOES
; DOES> behavior for single-byte assembler instructions: fetch the instance
; opcode, compile it with C-comma, then reset addressing mode with MEM.
DOCPU:
	.word	CAT
	.word	CCOM
	.word	MEM
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: BRK, [ASSEMBLER].
; Assembler word: emit the 6502 BRK instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_BRK_NFA:
	.byte	$84,"BRK",$AC
	.word	ASM_CPU_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOCPU
	.byte	0

; ---------------------------------------------------------------------------
; Dictionary: clc, [ASSEMBLER].
; Assembler word: emit the 6502 clc instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_CLC_NFA:
	.byte	$84,"CLC",$AC
	.word	ASM_BRK_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOCPU
	.byte	$18

; ---------------------------------------------------------------------------
; Dictionary: CLD, [ASSEMBLER].
; Assembler word: emit the 6502 CLD instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_CLD_NFA:
	.byte	$84,"CLD",$AC
	.word	ASM_CLC_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOCPU
	.byte	$D8

; ---------------------------------------------------------------------------
; Dictionary: CLI, [ASSEMBLER].
; Assembler word: emit the 6502 CLI instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_CLI_NFA:
	.byte	$84,"CLI",$AC
	.word	ASM_CLD_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOCPU
	.byte	$58

; ---------------------------------------------------------------------------
; Dictionary: CLV, [ASSEMBLER].
; Assembler word: emit the 6502 CLV instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_CLV_NFA:
	.byte	$84,"CLV",$AC
	.word	ASM_CLI_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOCPU
	.byte	$B8

; ---------------------------------------------------------------------------
; Dictionary: dex, [ASSEMBLER].
; Assembler word: emit the 6502 dex instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_DEX_NFA:
	.byte	$84,"DEX",$AC
	.word	ASM_CLV_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOCPU
	.byte	$CA

; ---------------------------------------------------------------------------
; Dictionary: dey, [ASSEMBLER].
; Assembler word: emit the 6502 dey instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_DEY_NFA:
	.byte	$84,"DEY",$AC
	.word	ASM_DEX_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOCPU
	.byte	$88

; ---------------------------------------------------------------------------
; Dictionary: inx, [ASSEMBLER].
; Assembler word: emit the 6502 inx instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_INX_NFA:
	.byte	$84,"INX",$AC
	.word	ASM_DEY_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOCPU
	.byte	$E8

; ---------------------------------------------------------------------------
; Dictionary: iny, [ASSEMBLER].
; Assembler word: emit the 6502 iny instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_INY_NFA:
	.byte	$84,"INY",$AC
	.word	ASM_INX_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOCPU
	.byte	$C8

; ---------------------------------------------------------------------------
; Dictionary: NOP, [ASSEMBLER].
; Assembler word: emit the 6502 NOP instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_NOP_NFA:
	.byte	$84,"NOP",$AC
	.word	ASM_INY_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOCPU
	.byte	$EA

; ---------------------------------------------------------------------------
; Dictionary: pha, [ASSEMBLER].
; Assembler word: emit the 6502 pha instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_PHA_NFA:
	.byte	$84,"PHA",$AC
	.word	ASM_NOP_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOCPU
	.byte	$48

; ---------------------------------------------------------------------------
; Dictionary: PHP, [ASSEMBLER].
; Assembler word: emit the 6502 PHP instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_PHP_NFA:
	.byte	$84,"PHP",$AC
	.word	ASM_PHA_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOCPU
	.byte	8

; ---------------------------------------------------------------------------
; Dictionary: pla, [ASSEMBLER].
; Assembler word: emit the 6502 pla instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_PLA_NFA:
	.byte	$84,"PLA",$AC
	.word	ASM_PHP_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOCPU
	.byte	$68

; ---------------------------------------------------------------------------
; Dictionary: PLP, [ASSEMBLER].
; Assembler word: emit the 6502 PLP instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_PLP_NFA:
	.byte	$84,"PLP",$AC
	.word	ASM_PLA_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOCPU
	.byte	$28

; ---------------------------------------------------------------------------
; Dictionary: RTI, [ASSEMBLER].
; Assembler word: emit the 6502 RTI instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_RTI_NFA:
	.byte	$84,"RTI",$AC
	.word	ASM_PLP_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOCPU
	.byte	$40

; ---------------------------------------------------------------------------
; Dictionary: rts, [ASSEMBLER].
; Assembler word: emit the 6502 rts instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_RTS_NFA:
	.byte	$84,"RTS",$AC
	.word	ASM_RTI_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOCPU
	.byte	$60

; ---------------------------------------------------------------------------
; Dictionary: sec, [ASSEMBLER].
; Assembler word: emit the 6502 sec instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_SEC_NFA:
	.byte	$84,"SEC",$AC
	.word	ASM_RTS_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOCPU
	.byte	$38

; ---------------------------------------------------------------------------
; Dictionary: SED, [ASSEMBLER].
; Assembler word: emit the 6502 SED instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_SED_NFA:
	.byte	$84,"SED",$AC
	.word	ASM_SEC_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOCPU
	.byte	$F8

; ---------------------------------------------------------------------------
; Dictionary: SEI, [ASSEMBLER].
; Assembler word: emit the 6502 SEI instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_SEI_NFA:
	.byte	$84,"SEI",$AC
	.word	ASM_SED_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOCPU
	.byte	$78

; ---------------------------------------------------------------------------
; Dictionary: tax, [ASSEMBLER].
; Assembler word: emit the 6502 tax instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_TAX_NFA:
	.byte	$84,"TAX",$AC
	.word	ASM_SEI_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOCPU
	.byte	$AA

; ---------------------------------------------------------------------------
; Dictionary: tay, [ASSEMBLER].
; Assembler word: emit the 6502 tay instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_TAY_NFA:
	.byte	$84,"TAY",$AC
	.word	ASM_TAX_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOCPU
	.byte	$A8

; ---------------------------------------------------------------------------
; Dictionary: tsx, [ASSEMBLER].
; Assembler word: emit the 6502 tsx instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_TSX_NFA:
	.byte	$84,"TSX",$AC
	.word	ASM_TAY_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOCPU
	.byte	$BA

; ---------------------------------------------------------------------------
; Dictionary: txa, [ASSEMBLER].
; Assembler word: emit the 6502 txa instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_TXA_NFA:
	.byte	$84,"TXA",$AC
	.word	ASM_TSX_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOCPU
	.byte	$8A

; ---------------------------------------------------------------------------
; Dictionary: txs, [ASSEMBLER].
; Assembler word: emit the 6502 txs instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_TXS_NFA:
	.byte	$84,"TXS",$AC
	.word	ASM_TXA_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOCPU
	.byte	$9A

; ---------------------------------------------------------------------------
; Dictionary: tya, [ASSEMBLER].
; Assembler word: emit the 6502 tya instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_TYA_NFA:
	.byte	$84,"TYA",$AC
	.word	ASM_TXS_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOCPU
	.byte	$98

; ---------------------------------------------------------------------------
; Dictionary: M/CPU [ASSEMBLER].
; Manual stack: ( n1/n2 --- ) (compiling assembler)
; Manual: An assembler defining word used to create assembler mnemonics that
; have multiple address modes HEX 1C6E 60 M/CPU adc, M/CPU creates the word
; adc, with two parameters. When adc later executes, it uses these
; parameters, along with stack values and the contents of MODE to calculate
; and assemble the correct op-code operands. 134
ASM_MCPU_NFA:
	.byte	$85,"M/CP",$D5
	.word	ASM_TYA_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	BUILD
	.word	CCOM
	.word	COMMA
	.word	DOES
; DOES> behavior for instructions with operands: instance data holds base
; opcode plus addressing-mode masks. Select zero-page/absolute form, validate
; the mode, compile the opcode and the needed operand bytes, then restore MEM
; mode.
DOMCPU:
	.word	DUP
	.word	ONEP
	.word	AT
	.word	LIT,$80
	.word	ANDD
	.word	ZBRAN,$A	; Pop flag; if zero branch to $AEEB (offset +10 from operand cell)
	.word	LIT,$10
	.word	MODE
	.word	PSTOR
	.word	OVER
	.word	LIT,$FF00
	.word	ANDD
	.word	UPMODE
	.word	UPMODE
	.word	ZBRAN,$E	; Pop flag; if zero branch to $AF07 (offset +14 from operand cell)
	.word	MEM
	.word	CR
	.word	LATES
	.word	IDDOT
	.word	THREE
	.word	ERROR
	.word	CAT
	.word	MODE
	.word	CAT
	.word	INDEX
	.word	PLUS
	.word	CAT
	.word	PLUS
	.word	CCOM
	.word	MODE
	.word	CAT
	.word	LIT,7
	.word	ANDD
	.word	ZBRAN,$1E	; Pop flag; if zero branch to $AF41 (offset +30 from operand cell)
	.word	MODE
	.word	CAT
	.word	LIT,$F
	.word	ANDD
	.word	LIT,7
	.word	LESS
	.word	ZBRAN,8	; Pop flag; if zero branch to $AF3F (offset +8 from operand cell)
	.word	CCOM
	.word	BRAN,4	; Jump to $AF41 (offset +4 from operand cell)
	.word	COMMA
	.word	MEM
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: adc, [ASSEMBLER].
; Assembler word: emit the 6502 adc instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_ADC_NFA:
	.byte	$84,"ADC",$AC
	.word	ASM_MCPU_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOMCPU
	.byte	$60,$6E,$1C

; ---------------------------------------------------------------------------
; Dictionary: and, [ASSEMBLER].
; Assembler word: emit the 6502 and instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_AND_NFA:
	.byte	$84,"AND",$AC
	.word	ASM_ADC_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOMCPU
	.byte	$20,$6E,$1C

; ---------------------------------------------------------------------------
; Dictionary: cmp, [ASSEMBLER].
; Assembler word: emit the 6502 cmp instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_CMP_NFA:
	.byte	$84,"CMP",$AC
	.word	ASM_AND_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOMCPU
	.byte	$C0,$6E,$1C

; ---------------------------------------------------------------------------
; Dictionary: eor, [ASSEMBLER].
; Assembler word: emit the 6502 eor instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_EOR_NFA:
	.byte	$84,"EOR",$AC
	.word	ASM_CMP_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOMCPU
	.byte	$40,$6E,$1C

; ---------------------------------------------------------------------------
; Dictionary: lda, [ASSEMBLER].
; Assembler word: emit the 6502 lda instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_LDA_NFA:
	.byte	$84,"LDA",$AC
	.word	ASM_EOR_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOMCPU
	.byte	$A0,$6E,$1C

; ---------------------------------------------------------------------------
; Dictionary: ora, [ASSEMBLER].
; Assembler word: emit the 6502 ora instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_ORA_NFA:
	.byte	$84,"ORA",$AC
	.word	ASM_LDA_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOMCPU
	.byte	$00,$6E,$1C

; ---------------------------------------------------------------------------
; Dictionary: sbc, [ASSEMBLER].
; Assembler word: emit the 6502 sbc instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_SBC_NFA:
	.byte	$84,"SBC",$AC
	.word	ASM_ORA_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOMCPU
	.byte	$E0,$6E,$1C

; ---------------------------------------------------------------------------
; Dictionary: sta, [ASSEMBLER].
; Assembler word: emit the 6502 sta instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_STA_NFA:
	.byte	$84,"STA",$AC
	.word	ASM_SBC_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOMCPU
	.byte	$80,$6C,$1C

; ---------------------------------------------------------------------------
; Dictionary: asl, [ASSEMBLER].
; Assembler word: emit the 6502 asl instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_ASL_NFA:
	.byte	$84,"ASL",$AC
	.word	ASM_STA_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOMCPU
	.byte	$01,$0D,$0D

; ---------------------------------------------------------------------------
; Dictionary: dec, [ASSEMBLER].
; Assembler word: emit the 6502 dec instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_DEC_NFA:
	.byte	$84,"DEC",$AC
	.word	ASM_ASL_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOMCPU
	.byte	$C1,$0C,$0C

; ---------------------------------------------------------------------------
; Dictionary: inc, [ASSEMBLER].
; Assembler word: emit the 6502 inc instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_INC_NFA:
	.byte	$84,"INC",$AC
	.word	ASM_DEC_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOMCPU
	.byte	$E1,$0C,$0C

; ---------------------------------------------------------------------------
; Dictionary: LSR, [ASSEMBLER].
; Assembler word: emit the 6502 LSR instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_LSR_NFA:
	.byte	$84,"LSR",$AC
	.word	ASM_INC_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOMCPU
	.byte	$41,$0D,$0D

; ---------------------------------------------------------------------------
; Dictionary: rol, [ASSEMBLER].
; Assembler word: emit the 6502 rol instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_ROL_NFA:
	.byte	$84,"ROL",$AC
	.word	ASM_LSR_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOMCPU
	.byte	$21,$0D,$0D

; ---------------------------------------------------------------------------
; Dictionary: ROR, [ASSEMBLER].
; Assembler word: emit the 6502 ROR instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_ROR_NFA:
	.byte	$84,"ROR",$AC
	.word	ASM_ROL_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOMCPU
	.byte	$61,$0D,$0D

; ---------------------------------------------------------------------------
; Dictionary: stx, [ASSEMBLER].
; Assembler word: emit the 6502 stx instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_STX_NFA:
	.byte	$84,"stx",$AC
	.word	ASM_ROR_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOMCPU
	.byte	$81,$14,$04

; ---------------------------------------------------------------------------
; Dictionary: CPX, [ASSEMBLER].
; Assembler word: emit the 6502 CPX instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_CPX_NFA:
	.byte	$84,"CPX",$AC
	.word	ASM_STX_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOMCPU
	.byte	$E0,$86,$04

; ---------------------------------------------------------------------------
; Dictionary: cpy, [ASSEMBLER].
; Assembler word: emit the 6502 cpy instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_CPY_NFA:
	.byte	$84,"CPY",$AC
	.word	ASM_CPX_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOMCPU
	.byte	$C0,$86,$04

; ---------------------------------------------------------------------------
; Dictionary: ldx, [ASSEMBLER].
; Assembler word: emit the 6502 ldx instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_LDX_NFA:
	.byte	$84,"LDX",$AC
	.word	ASM_CPY_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOMCPU
	.byte	$A2,$96,$14

; ---------------------------------------------------------------------------
; Dictionary: ldy, [ASSEMBLER].
; Assembler word: emit the 6502 ldy instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_LDY_NFA:
	.byte	$84,"LDY",$AC
	.word	ASM_LDX_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOMCPU
	.byte	$A0,$8E,$0C

; ---------------------------------------------------------------------------
; Dictionary: sty, [ASSEMBLER].
; Assembler word: emit the 6502 sty instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_STY_NFA:
	.byte	$84,"STY",$AC
	.word	ASM_LDY_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOMCPU
	.byte	$80,$8C,$04

; ---------------------------------------------------------------------------
; Dictionary: jsr, [ASSEMBLER].
; Assembler word: emit the 6502 jsr instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_JSR_NFA:
	.byte	$84,"JSR",$AC
	.word	ASM_STY_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOMCPU
	.byte	$14,$80,$04

; ---------------------------------------------------------------------------
; Dictionary: jmp, [ASSEMBLER].
; Assembler word: emit the 6502 jmp instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
JMPP_NFA:
	.byte	$84,"JMP",$AC
	.word	ASM_JSR_NFA	; LFA: previous name field in this vocabulary chain
JMPP:
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOMCPU
	.byte	$40,$80,$84

; ---------------------------------------------------------------------------
; Dictionary: BIT, [ASSEMBLER].
; Assembler word: emit the 6502 BIT instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
ASM_BIT_NFA:
	.byte	$84,"BIT",$AC
	.word	JMPP_NFA	; LFA: previous name field in this vocabulary chain
	.word	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.word	DOMCPU
	.byte	$84,$00,$00

; ---------------------------------------------------------------------------
; Dictionary: BEGIN, [ASSEMBLER]; immediate (executes during compilation).
; Manual stack: ( --- a1/n1 ) (assembling)
; Manual: ( --- ) (run-time) Occurs in a code definition in the form: BEGIN,
; ... n2 UNTIL, At run-time, BEGIN, leaves the dictionary pointer address a1
; and the value n1-1 for later testing of conditional pairing by UNTIL,.
ASM_BEGIN_NFA:
	.byte	$C6,"BEGIN",$AC
	.word	ASM_BIT_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	HERE
	.word	ONE
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: UNTIL, [ASSEMBLER]; immediate (executes during compilation).
; Manual stack: ( a1/n1/n2 --- ) (assembling)
; Manual: ( --- ) (run-time) Occurs in a code definition in the form: BEGIN
; .... n2 UNTIL, At run-time, UNTIL, controls the conditional branching back
; to BEGIN,. If the processor status bit specified by condition code n=2 is
; false, execution returns to BEGIN,; otherwise execution continues ahead. At
; assembly time, UNTIL, assembles a conditional relative branch to address
; a1, based on condition code n2. The number n1=1, and is used for error
; checking.
ASM_UNTIL_NFA:
	.byte	$C6,"UNTIL",$AC
	.word	ASM_BEGIN_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	QEXEC
	.word	TOR
	.word	ONE
	.word	QPAIR
	.word	RFROM
	.word	CCOM
	.word	HERE
	.word	ONEP
	.word	SUBB
	.word	CCOM
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: IF, [ASSEMBLER]; immediate (executes during compilation).
; Manual stack: ( b1 --- a1/n1 )(assembly time)
; Manual: Occurs within a code definition, in the following form: n1 IF,
; (true part) ELSE, (false part) ENDIF, At run-time, IF branches based on the
; condition code n1<0< or 0= or CS or OVS). If the specified processor status
; is true, execution continues ahead. Otherwise branching occurs just after
; ELSE, or ENDIF, when ELSE, is not present. At ELSE, execution resumes at
; the corresponding ENDIF,. When assembling, IF, creates an unresolved
; forward branch based on the condition code n1, and leaves address a1 and
; n1=2 for resolution of the branch by the corresponding ELSE, or ENDIF,.
; Conditionals may be nested.
ASM_IF_NFA:
	.byte	$C3,"IF",$AC
	.word	ASM_UNTIL_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	CCOM
	.word	HERE
	.word	ZERO
	.word	CCOM
	.word	TWO
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ENDIF, [ASSEMBLER]; immediate (executes during compilation).
; Manual stack: ( a1/n1 --- ) (assembly-time)
; Manual: ( --- ) Occurs in a code definition in the form: n2 IF, (true part)
; ELSE, (false part) ENDIF, At run-time ENDIF, marks the conclusion of a
; conditional structure. Execution of either the true part or the false part
; resumes the following ENDIF,. When assembling, address all and n1=2 are
; used to resolve the pending forward branch to ENDIF,.
ASM_ENDIF_NFA:
	.byte	$C6,"ENDIF",$AC
	.word	ASM_IF_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	QEXEC
	.word	TWO
	.word	QPAIR
	.word	HERE
	.word	OVER
	.word	CAT
	.word	ZBRAN,$A	; Pop flag; if zero branch to $B0F0 (offset +10 from operand cell)
	.word	SWAP
	.word	STORE
	.word	BRAN,$C	; Jump to $B0FA (offset +12 from operand cell)
	.word	OVER
	.word	ONEP
	.word	SUBB
	.word	SWAP
	.word	CSTOR
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ELSE, [ASSEMBLER]; immediate (executes during compilation).
; Manual stack: ( --- a1/n1 ) (assembling)
; Manual: ( --- ) (run-time) Occurs within a code definition in the form: n2
; IF, (true part) ELSE, (false part) ENDIF, At run-time, if the condition
; code specified by n2 is false, execution skips to the machine code
; following ELSE,. At assembly time ELSE, assembles a forward jump to just
; after ENDIF, and resolves a pending forward branch from IF,. The values
; n1=n2 are used for error checking of conditional pairing.
ASM_ELSE_NFA:
	.byte	$C5,"ELSE",$AC
	.word	ASM_ENDIF_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	TWO
	.word	QPAIR
	.word	HERE
	.word	ONEP
	.word	ONE
	.word	JMPP
	.word	SWAP
	.word	HERE
	.word	OVER
	.word	ONEP
	.word	SUBB
	.word	SWAP
	.word	CSTOR
	.word	TWO
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: NOT [ASSEMBLER].
; Manual stack: ( n1 --- n2 ) (assembly-time)
; Manual: When assembling, reverse the condition code n1 for the following
; conditional, returning n2 the complemented condition code. For example: 0
; NOT IF, (true part) ENDIF, will branch based on "not equal to zero."
ASM_NOT_NFA:
	.byte	$83,"NO",$D4
	.word	ASM_ELSE_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	LIT,$20
	.word	PLUS
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: CS [ASSEMBLER].
; Manual stack: ( --- n1 ) (assembling)
; Manual: Specify that the Immediately following conditional will branch
; based on if the processor carry is set (C=1). The flag n1 is left at
; assembly time; there is no run-time effect on the stack.
ASM_CS_NFA:
	.byte	$82,"C",$D3
	.word	ASM_NOT_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCON	; CFA: constant; push the following 16-bit value
	.word	$90

; ---------------------------------------------------------------------------
; Dictionary: 0= [ASSEMBLER].
; Manual stack: ( --- n1 ) (assembling)
; Manual: Specify that the immediately following conditional will branch
; based on the processor status bit being equal to zero (Z=1). The flag n1 is
; left at assembly time; there is no run-time effect on the stack.
ASM_ZERO_EQUAL_NFA:
	.byte	$82,"0",$BD
	.word	ASM_CS_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCON	; CFA: constant; push the following 16-bit value
	.word	$D0

; ---------------------------------------------------------------------------
; Dictionary: 0< [ASSEMBLER].
; Manual stack: ( --- n1 ) (assembling)
; Manual: Specify that the immediately following conditional will branch
; based on the processor status bit being negative (N=1), i.e., less than
; zero. The flag n1 is left at assembly time; there is no run-time effect on
; the stack.
ASM_ZERO_LESS_NFA:
	.byte	$82,"0",$BC
	.word	ASM_ZERO_EQUAL_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCON	; CFA: constant; push the following 16-bit value
	.word	$10

; ---------------------------------------------------------------------------
; Dictionary: >= [ASSEMBLER].
; Manual stack: ( --- n1 ) (assembling)
; Manual: Specify that the immediately following conditional will branch
; based on the processor status bit carry being set (see =1). The flag n1 is
; left at assembly time. There is no run-time effect on the stack.
ASM_GREATER_EQUAL_NFA:
	.byte	$82,">",$BD
	.word	ASM_ZERO_LESS_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCON	; CFA: constant; push the following 16-bit value
	.word	$90

; ---------------------------------------------------------------------------
; Dictionary: OVS [ASSEMBLER].
; Manual stack: ( --- n1 ) (assembling)
; Manual: Specify that the immediately following conditional branch based on
; the processor overflow flag is set (V=1). The flag n1 is left at assembly
; time; there is no run-time effect on the stack.
OVS_NFA:
	.byte	$83,"OV",$D3
	.word	ASM_GREATER_EQUAL_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCON	; CFA: constant; push the following 16-bit value
	.word	$70

; ---------------------------------------------------------------------------
; Dictionary: END-CODE [ASSEMBLER]; immediate (executes during compilation).
; Manual: An error check word marking the end of a CODE definition.
; Successful execution to and including END-CODE will unSMUDGE the most
; recent CURRENT vocabulary definition, making it available for execution.
; END-CODE also exits the ASSEMBLER making CONTEXT the same as CURRENT. This
; word previously was named C;.
END_CODE_NFA:
	.byte	$C8,"END-COD",$C5
	.word	OVS_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	CURR
	.word	AT
	.word	CONT
	.word	STORE
	.word	QEXEC
	.word	QCSP
	.word	SMUDGE
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: CODE [FORTH]; immediate (executes during compilation).
; Manual stack: ( --- t )
; Manual: A defining word used in the form: CODE (name) ... END-CODE To
; create a dictionary entry for (name) in the CURRENT vocabulary. Name's code
; field contains the address of the parameter field. When (name) Is later
; executed, the machine code in this parameter field will execute. The
; CONTEXT vocabulary is made ASSEMBLER, to make available op-code mnemonics.
CODE_NFA:
	.byte	$C4,"COD",$C5
	.word	FORG_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	QEXEC
	.word	CREAT
	.word	$871
	.word	MEM
	.word	SCSP
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: DEPTH [FORTH].
; Manual stack: ( --- n1 )
; Manual: Returns the current depth of the data stack as value n1. The actual
; depth of the stack is increased by one element.
DEPT_NFA:
	.byte	$85,"DEPT",$C8
	.word	CODE_NFA	; LFA: previous name field in this vocabulary chain
DEPTH:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	SPAT
	.word	LIT,TOS
	.word	SWAP
	.word	SUBB
	.word	TWO
	.word	SLASH
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: .S [FORTH].
; Manual stack: ( --- )
; Manual: Prints the current contents of the data stack on the screen in the
; current base, without destroying its contents.
DOTS_NFA:
	.byte	$82,".",$D3
	.word	DEPT_NFA	; LFA: previous name field in this vocabulary chain
DOTS:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	QSTAC
	.word	DEPTH
	.word	ZBRAN,$24	; Pop flag; if zero branch to $B1DF (offset +36 from operand cell)
	.word	SPAT
	.word	TWO
	.word	SUBB
	.word	LIT,$5E
	.word	PDO
	.word	I
	.word	AT
	.word	LIT,5
	.word	DOTR
	.word	LIT,$FFFE
	.word	PPLOO,$FFF0	; Add stack increment; if continuing branch to $B1C9 (offset -16 from operand cell)
	.word	BRAN,$C	; Jump to $B1E9 (offset +12 from operand cell)
	.word	PDOTQ	; Print counted inline text; resume after its payload
	.byte	7
	.byte	" EMPTY "
	.word	SEMIS	; Return to caller thread

; ===========================================================================
; FORTH SINGLE-STEPPER and DECOMPILER
; ===========================================================================

; ---------------------------------------------------------------------------
; Dictionary: ERP [SYSTEM].
; Manual: One of a group of EMULATION words, used by the DEBUGGER. Not a user
; word. 126
ERP_NFA:
	.byte	$83,"ER",$D0
	.word	PRON_NFA	; LFA: previous name field in this vocabulary chain
ERP:
	.word	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.word	$CC	; User offset $00CC; initial address $0A0C

; ---------------------------------------------------------------------------
; Dictionary: EIP [SYSTEM].
; Manual: One of a group of EMULATION words, used by the DEBUGGER. Not a user
; word.
EIP_NFA:
	.byte	$83,"EI",$D0
	.word	ERP_NFA	; LFA: previous name field in this vocabulary chain
EIP:
	.word	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.word	$CE	; User offset $00CE; initial address $0A0E

; ---------------------------------------------------------------------------
; Dictionary: ERP! [SYSTEM].
; Manual: One of a group of EMULATION words, used by the DEBUGGER. Not a user
; word.
ERPSTO_NFA:
	.byte	$84,"ERP",$A1
	.word	EIP_NFA	; LFA: previous name field in this vocabulary chain
ERPSTO:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	BLKTBL
	.word	TWO
	.word	SUBB
	.word	ERP
	.word	STORE
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: E>R [SYSTEM].
; Manual: One of a group of EMULATION words, used by the DEBUGGER. Not a user
; word.
ETOR_NFA:
	.byte	$83,"E>",$D2
	.word	ERPSTO_NFA	; LFA: previous name field in this vocabulary chain
ETOR:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	ERP
	.word	AT
	.word	STORE
	.word	LIT,$FFFE
	.word	ERP
	.word	PSTOR
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ER> [SYSTEM].
; Manual: One of a group of EMULATION words, used by the DEBUGGER. Not a user
; word.
ERFROM_NFA:
	.byte	$83,"ER",$BE
	.word	ETOR_NFA	; LFA: previous name field in this vocabulary chain
ERFROM:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	TWO
	.word	ERP
	.word	PSTOR
	.word	ERP
	.word	AT
	.word	BLKTBL
	.word	TWO
	.word	SUBB
	.word	GREAT
	.word	ZBRAN,$16	; Pop flag; if zero branch to $B25E (offset +22 from operand cell)
	.word	ERPSTO
	.word	PDOTQ	; Print counted inline text; resume after its payload
	.byte	11
	.byte	"RSTK EMPTY "
	.word	SPSTO
	.word	QUIT
	.word	ERP
	.word	AT
	.word	AT
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: EIP+ [SYSTEM].
; Manual: One of a group of EMULATION words, used by the DEBUGGER. Not a user
; word.
EIPPL_NFA:
	.byte	$84,"EIP",$AB
	.word	ERFROM_NFA	; LFA: previous name field in this vocabulary chain
EIPPL:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	TWO
	.word	EIP
	.word	PSTOR
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: EBR [SYSTEM].
; Implementation: Emulated BRANCH: fetch and display the displacement at EIP,
; then add it to EIP.
EBR_NFA:
	.byte	$83,"EB",$D2
	.word	EIPPL_NFA	; LFA: previous name field in this vocabulary chain
EBR:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	EIP
	.word	AT
	.word	AT
	.word	DUP
	.word	DOT
	.word	EIP
	.word	PSTOR
	.word	SEMIS	; Return to caller thread

EZBRAN:
	.word	DOCOL
	.word	ZBRAN,8	; Pop flag; if zero branch to $B29B (offset +8 from operand cell)
	.word	EIPPL
	.word	BRAN,4	; Jump to $B29D (offset +4 from operand cell)
	.word	EBR
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: EI [SYSTEM].
; Manual: One of a group of EMULATION words, used by the DEBUGGER. Not a user
; word.
EI_NFA:
	.byte	$82,"E",$C9
	.word	EBR_NFA	; LFA: previous name field in this vocabulary chain
EI:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	ERP
	.word	AT
	.word	TWOP
	.word	AT
	.word	SEMIS	; Return to caller thread

ELIT:
	.word	DOCOL
	.word	EIP
	.word	AT
	.word	AT
	.word	EIPPL
	.word	SEMIS	; Return to caller thread

ECLIT:
	.word	DOCOL
	.word	EIP
	.word	AT
	.word	CAT
	.word	ONE
	.word	EIP
	.word	PSTOR
	.word	SEMIS	; Return to caller thread

EALIT:
	.word	DOCOL
	.word	EIP
	.word	AT
	.word	COUNT
	.word	TDUP
	.word	PLUS
	.word	EIP
	.word	STORE
	.word	TDUP
	.word	TYPE
	.word	SEMIS	; Return to caller thread

EPDOTQ:
	.word	DOCOL
	.word	EALIT
	.word	TDROP
	.word	SEMIS	; Return to caller thread

EPDO:
	.word	DOCOL
	.word	SWAP
	.word	ETOR
	.word	ETOR
	.word	SEMIS	; Return to caller thread

EPPLOO:
	.word	DOCOL
	.word	ERFROM
	.word	OVER
	.word	PLUS
	.word	ERFROM
	.word	TDUP
	.word	ETOR
	.word	ETOR
	.word	ROT
	.word	ZLESS
	.word	ZBRAN,6	; Pop flag; if zero branch to $B310 (offset +6 from operand cell)
	.word	SWAP
	.word	ONEP
	.word	LESS
	.word	ZBRAN,8	; Pop flag; if zero branch to $B31C (offset +8 from operand cell)
	.word	EBR
	.word	BRAN,$C	; Jump to $B326 (offset +12 from operand cell)
	.word	ERFROM
	.word	DROP
	.word	ERFROM
	.word	DROP
	.word	EIPPL
	.word	SEMIS	; Return to caller thread

EPLOOP:
	.word	DOCOL
	.word	ONE
	.word	EPPLOO
	.word	SEMIS	; Return to caller thread

ELEAV:
	.word	DOCOL
	.word	ERFROM
	.word	DROP
	.word	ERFROM
	.word	DROP
	.word	EI
	.word	ETOR
	.word	SEMIS	; Return to caller thread

ECOMP:
	.word	DOCOL
	.word	EIP
	.word	AT
	.word	AT
	.word	DUP
	.word	TWOP
	.word	NFA
	.word	IDDOT
	.word	COMMA
	.word	EIPPL
	.word	SEMIS	; Return to caller thread

; Forth tracer substitution table: count byte 16 followed by sixteen
; original-CFA / emulation-CFA pairs. CND uses these to emulate words that
; alter IP or the return stack. This is a Forth thread emulator, not a 6502
; CPU emulator.
EMULATION_CFA_TABLE:
	.byte	16

	.word	BRAN
	.word	EBR

	.word	I
	.word	EI

	.word	R
	.word	EI

	.word	RPSTO
	.word	ERPSTO

	.word	TOR
	.word	ETOR

	.word	RFROM
	.word	ERFROM

	.word	COMP
	.word	ECOMP	; Inline CFA operand consumed by COMPILE

	.word	LEAVE
	.word	ELEAV

	.word	PLOOP
	.word	EPLOOP

	.word	PPLOO
	.word	EPPLOO

	.word	PDO
	.word	EPDO

	.word	PDOTQ	; Print counted inline text; resume after its payload
	.word	EPDOTQ

	.word	ALIT
	.word	EALIT

	.word	CLIT	; Push following inline byte, zero-extended
	.word	ECLIT

	.word	LIT	; Push following inline 16-bit cell
	.word	ELIT	; Inline literal value, not a call

	.word	ZBRAN
	.word	EZBRAN

; ---------------------------------------------------------------------------
; Dictionary: CND [SYSTEM].
; Manual stack: ( a1 --- a2 )
; Manual: This is an emulator primitive, which converts the address of a
; selected group of emulated words from their real code field address of the
; emulation word that is their equivalent. Not a user word.
CND_NFA:
	.byte	$83,"CN",$C4
	.word	EI_NFA	; LFA: previous name field in this vocabulary chain
CND:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	LIT,EMULATION_CFA_TABLE
	.word	COUNT
	.word	LIT,4
	.word	STAR
	.word	ZERO
	.word	PDO
	.word	TDUP
	.word	I
	.word	PLUS
	.word	AT
	.word	EQUAL
	.word	ZBRAN,$E	; Pop flag; if zero branch to $B3C9 (offset +14 from operand cell)
	.word	I
	.word	PLUS
	.word	TWOP
	.word	AT
	.word	SWAP
	.word	LEAVE
	.word	LIT,4
	.word	PPLOO,$FFE0	; Add stack increment; if continuing branch to $B3AF (offset -32 from operand cell)
	.word	DROP
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ERR [SYSTEM].
; Manual stack: ( --- )
; Manual: This word prints the error message CODE DEFINITION, when TRACE or
; EMULATE are used on a CODE WORD. This prevents a crash, if an attempt was
; actually made to trace these words.
ERR_NFA:
	.byte	$83,"ER",$D2
	.word	CND_NFA	; LFA: previous name field in this vocabulary chain
ERR:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	PDOTQ	; Print counted inline text; resume after its payload
	.byte	8
	.byte	"CODE DEF"
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: 'STEP [SYSTEM].
; Manual stack: ( --- a1 )
; Manual: Returns the address of the execution variable used to control the
; STEP action. The word STEP gets vectored to an error message if you attempt
; to TRACE a code word. Normally, 'STEP contains the CFA of (STEP).
TSTEP_NFA:
	.byte	$85,$27,"STE",$D0
	.word	ERR_NFA	; LFA: previous name field in this vocabulary chain
TSTEP:
	.word	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.word	$D0	; User offset $00D0; initial address $0A10

; ---------------------------------------------------------------------------
; Dictionary: 'CONT [SYSTEM].
; Manual stack: ( --- a1 )
; Manual: Returns the address of the execution variable used to control the
; CONT action. The word CONT gets vectored to an error message if you attempt
; to TRACE a code word. Normally, 'CONT contains the CFA of (CONT).
TCONT_NFA:
	.byte	$85
	.byte	$27,"CON",$D4
	.word	TSTEP_NFA	; LFA: previous name field in this vocabulary chain
TCONT:
	.word	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.word	$D2	; User offset $00D2; initial address $0A12

; ---------------------------------------------------------------------------
; Dictionary: (STEP) [SYSTEM].
; Manual stack: ( --- )
; Manual: Performs a single step through the currently selected TRACE word.
; This is the function to which STEP is vectored, when a high level word is
; being traced. Not normally used by the user.
PSTEP_NFA:
	.byte	$86,"(STEP",$A9
	.word	TCONT_NFA	; LFA: previous name field in this vocabulary chain
PSTEP:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	EIP
	.word	AT
	.word	AT
	.word	DUP
	.word	TWOP
	.word	NFA
	.word	IDDOT
	.word	DUP
	.word	LIT,SEMIS
	.word	SUBB
	.word	ZBRAN,$15	; Pop flag; if zero branch to $B43A (offset +21 from operand cell)
	.word	EIPPL
	.word	CND
	.word	EXEC
	.word	TAB
	.word	PDOTQ	; Print counted inline text; resume after its payload
	.byte	2
	.byte	">>"
	.word	DOTS
	.word	BRAN,$F	; Jump to $B447 (offset +15 from operand cell)
	.word	DROP
	.word	PDOTQ	; Print counted inline text; resume after its payload
	.byte	8
	.byte	"DEF END "
	.word	CR
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: (CONT) [SYSTEM].
; Manual stack: ( --- )
; Manual: Performs a continuous emulation through the currently selected
; TRACE word. This is the low level operation to which CONT gets vectored
; when a high level FORTH word is TRACED. This word is not normally used by
; the user at the keyboard.
PCONT_NFA:
	.byte	$86,"(CONT",$A9
	.word	PSTEP_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
PCONT:
	.word	CR
	.word	PSTEP
	.word	EIP
	.word	AT
	.word	AT
	.word	LIT,SEMIS
	.word	EQUAL
	.word	QTER
	.word	ORR
	.word	ZBRAN,$FFEC	; Pop flag; if zero branch to $B458 (offset -20 from operand cell)
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: STEP [FORTH].
; Manual stack: ( --- )
; Manual: Performs a TRACE single step, after a trace has been stopped, or a
; word has been selected for emulation with the EMULATE word.
STEP_NFA:
	.byte	$84,"STE",$D0
	.word	DOTS_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	TSTEP
	.word	AT
	.word	EXEC
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: CONT [FORTH].
; Manual stack: ( --- )
; Manual: This is a vectored word which causes all of a definition to be
; traced after a trace has been interpreted, or an EMULATE command has been
; issued. As the trace scrolls up the screen, it can be interrupted at any
; time, by pressing any character key. To continue after interruption, simply
; enter CONT followed by a carriage return.
CONTT_NFA:
	.byte	$84,"CON",$D4
	.word	STEP_NFA	; LFA: previous name field in this vocabulary chain
CONTT:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	TCONT
	.word	AT
	.word	EXEC
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: EMULATE [FORTH].
; Manual stack: ( --- t )
; Manual: Selects the word following EMULATE as the word to be traced by the
; select debugger. Revectors 'CONT and 'STEP to (CONT) and (STEP) if the word
; Is a high level word; otherwise vectors them to an error message routine.
; 125
EMULAT_NFA:
	.byte	$87,"EMULAT",$C5
	.word	CONTT_NFA	; LFA: previous name field in this vocabulary chain
; Tracer engine: initialize EIP and emulated return-stack state, classify the
; next CFA with CND, and run either its special emulation handler or its
; normal behavior. STEP and CONT control advancement through these Forth
; tokens.
EMULAT:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	TICK
	.word	CFA
	.word	DUP
	.word	EIP
	.word	STORE
	.word	AT
	.word	LIT,HEX
	.word	AT
	.word	SUBB
	.word	ZBRAN,$27	; Pop flag; if zero branch to $B4DB (offset +39 from operand cell)
	.word	CR
	.word	PDOTQ	; Print counted inline text; resume after its payload
	.byte	12
	.byte	"CODE DEF !! "
	.word	LIT,ERR+2
	.word	CFA
	.word	DUP
	.word	TSTEP
	.word	STORE
	.word	TCONT
	.word	STORE
	.word	BRAN,$1A	; Jump to $B4F3 (offset +26 from operand cell)
	.word	EIPPL
	.word	ERPSTO
	.word	LIT,PSTEP+2
	.word	CFA
	.word	TSTEP
	.word	STORE
	.word	LIT,PCONT
	.word	CFA
	.word	TCONT
	.word	STORE
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: TRACE [FORTH].
; Manual stack: ( --- t )
; Manual: Lists the lines of a definition of the word following TRACE.
; Performs the trace in the continuous mode, with vertical scrolling and
; stack output at each step.
TRACE_NFA:
	.byte	$85,"TRAC",$C5
	.word	EMULAT_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	EMULAT
	.word	CONTT
	.word	SEMIS	; Return to caller thread

;	PICK

; Dictionary: PICK [FORTH].
; Manual stack: ( n1 --- n2 )
; Manual: Picks element n1 from the data stack and leaves it as value n2. One
; (1) PICK is equivalent to DUP, and two (2) PICK is equivalent to OVER, etc.
PICK_NFA:
	.byte	$84,"PIC",$CB
	.word	TRACE_NFA	; LFA: previous name field in this vocabulary chain
PICK:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	TWO
	.word	STAR
	.word	SPAT
	.word	PLUS
	.word	AT
	.word	SEMIS	; Return to caller thread

SOURCE_MATCH:
	.word	DOCOL
	.word	THREE
	.word	PICK
	.word	EQUAL
	.word	ORR
	.word	SEMIS	; Return to caller thread

SOURCE_CONTINUE:
	.word	DOCOL
	.word	DUP
	.word	AT
	.word	TWOP
	.word	ZERO
	.word	LIT,SEMIS+2
	.word	SOURCE_MATCH
	.word	LIT,PSCOD+2
	.word	SOURCE_MATCH
	.word	LIT,QUIT+2
	.word	SOURCE_MATCH
	.word	QTER
	.word	ORR
	.word	SWAP
	.word	DROP
	.word	ZEQU
	.word	SEMIS	; Return to caller thread

SOURCE_OPERAND:
	.word	DOCOL
	.word	DUP
	.word	TWOP
	.word	SWAP
	.word	AT
	.word	TWOP
	.word	ZERO
	.word	LIT,COMP+2
	.word	SOURCE_MATCH
	.word	ZBRAN,$16	; Pop flag; if zero branch to $B57A (offset +22 from operand cell)
	.word	DROP
	.word	DUP
	.word	AT
	.word	TWOP
	.word	NFA
	.word	IDDOT
	.word	TWOP
	.word	SPACE
	.word	BRAN,$82	; Jump to $B5FA (offset +130 from operand cell)
	.word	ZERO
	.word	LIT,CLIT+2
	.word	SOURCE_MATCH
	.word	ZBRAN,$12	; Pop flag; if zero branch to $B596 (offset +18 from operand cell)
	.word	DROP
	.word	DUP
	.word	CAT
	.word	DOT
	.word	ONEP
	.word	SPACE
	.word	BRAN,$66	; Jump to $B5FA (offset +102 from operand cell)
	.word	ZERO
	.word	LIT,PDOTQ+2
	.word	SOURCE_MATCH
	.word	LIT,ALIT+2
	.word	SOURCE_MATCH
	.word	ZBRAN,$1E	; Pop flag; if zero branch to $B5C4 (offset +30 from operand cell)
	.word	DROP
	.word	DUP
	.word	COUNT
	.word	DUP
	.word	ROT
	.word	SWAP
	.word	TYPE
	.word	PLUS
	.word	ONEP
	.word	LIT,5
	.word	SPACS
	.word	BRAN,$38	; Jump to $B5FA (offset +56 from operand cell)
	.word	ZERO
	.word	LIT,LIT+2
	.word	SOURCE_MATCH
	.word	LIT,BRAN+2
	.word	SOURCE_MATCH
	.word	LIT,ZBRAN+2
	.word	SOURCE_MATCH
	.word	LIT,PPLOO+2
	.word	SOURCE_MATCH
	.word	LIT,PLOOP+2
	.word	SOURCE_MATCH
	.word	ZBRAN,$12	; Pop flag; if zero branch to $B5F8 (offset +18 from operand cell)
	.word	DROP
	.word	DUP
	.word	AT
	.word	DOT
	.word	SPACE
	.word	TWOP
	.word	BRAN,4	; Jump to $B5FA (offset +4 from operand cell)
	.word	DROP
	.word	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: SOURCE [FORTH].
; Manual stack: ( --- )
; Manual: Decompiles the word specified by the text following SOURCE, to its
; sequence of high level steps.
SOURCE_NFA:
	.byte	$86,"SOURC",$C5
	.word	PICK_NFA	; LFA: previous name field in this vocabulary chain
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	TICK
	.word	DUP
	.word	CFA
	.word	AT
	.word	LIT,HEX+2
	.word	CFA
	.word	AT
	.word	EQUAL
	.word	ZBRAN,$78	; Pop flag; if zero branch to $B693 (offset +120 from operand cell)
	.word	PDOTQ	; Print counted inline text; resume after its payload
	.byte	3
	.byte	" : "
	.word	DUP
	.word	NFA
	.word	IDDOT
	.word	SPACE
	.word	DUP
	.word	DUP
	.word	AT
	.word	TWOP
	.word	NFA
	.word	DUP
	.word	CAT
	.word	LIT,$40
	.word	ANDD
	.word	TWO
	.word	SPACS
	.word	ZBRAN,$F	; Pop flag; if zero branch to $B654 (offset +15 from operand cell)
	.word	PDOTQ	; Print counted inline text; resume after its payload
	.byte	10
	.byte	"[COMPILE] "
	.word	IDDOT
	.word	SOURCE_CONTINUE
	.word	ZBRAN,$16	; Pop flag; if zero branch to $B670 (offset +22 from operand cell)
	.word	SOURCE_OPERAND
	.word	OUT
	.word	AT
	.word	CSLL
	.word	GREAT
	.word	ZBRAN,4	; Pop flag; if zero branch to $B66C (offset +4 from operand cell)
	.word	CR
	.word	BRAN,$FFBF	; Jump to $B62D (offset -65 from operand cell)
	.word	DROP
	.word	DUP
	.word	NFA
	.word	AT
	.word	LIT,$40
	.word	ANDD
	.word	ZBRAN,$F	; Pop flag; if zero branch to $B68F (offset +15 from operand cell)
	.word	PDOTQ	; Print counted inline text; resume after its payload
	.byte	10
	.byte	"IMMEDIATE "
	.word	BRAN,4	; Jump to $B695 (offset +4 from operand cell)
	.word	ERR
	.word	DROP
	.word	CR
	.word	SEMIS	; Return to caller thread

;	MSREG

; ; ---------------------------------------------------------------------------
; ; SID SOUND SHADOW and CONTROL WORDS
; ; ---------------------------------------------------------------------------
; ; Dictionary: MSREG [SYSTEM].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- a1 )
; ; Manual: A system constant which returns the address of the memory area that
; ; is a copy of the SID chip sound register. This array is maintained to allow
; ; both reading and writing to the SID chip registers.
; MSREG_NFA:
; 	.byte	$85,"MSRE",$C7
; 	.word	PCONT_NFA	; LFA: previous name field in this vocabulary chain
; ; SID software shadow at $779A. Most setters modify this RAM image because
; ; SID control registers cannot be read back normally. S! copies 32 bytes to
; ; SID hardware; setters alone do not necessarily change the sound
; ; immediately.
; MSREG:
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: SBASE [SYSTEM].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- a1 )
; ; Manual: A system constant which returns the base address a1 of the SID
; ; chip.
; SBASE_NFA:
; 	.byte	$85,"SBAS",$C5
; 	.word	MSREG_NFA	; LFA: previous name field in this vocabulary chain
; SBASE:
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: CV [SYSTEM].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- a1 )
; ; Manual: Returns the base address of the currently selected voice of the
; ; sound system.
; CV_NFA:
; 	.byte	$82,"C",$D6
; 	.word	SBASE_NFA	; LFA: previous name field in this vocabulary chain
; CV:
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: WFORM [SYSTEM].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual: A defining word used to create many of the sound control words. Not
; ; a user word. 151
; WFORM_NFA:
; 	.byte	$85,"WFOR",$CD
; 	.word	CV_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: S! [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- )
; ; Manual: A sound system primitive, which moves the contents of the memory
; ; copy of the SID chip, to the actual SID chip registers. This word must be
; ; executed whenever a change 141 is made to the SID chip registers. It is not
; ; done automatically, because there would then be a heavy speed penalty for
; ; each sound word executed. As a result, this word is used after a group of
; ; changes are performed to cause them to all have effect at once.
; SSTOR_NFA:
; 	.byte	$82,"S",$A1
; 	.word	SOURCE_NFA	; LFA: previous name field in this vocabulary chain
; SSTOR:
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: SINIT [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- )
; ; Manual: This is the sound initialization word. It must be executed before
; ; any other operations can be done to the sound system.
; SINIT_NFA:
; 	.byte	$85,"SINI",$D4
; 	.word	SSTOR_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: PWIDTH! [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( n1 --- )
; ; Manual: Sets the PULSE width register value for voice #1, in the range 0 to
; ; 4095. See S!
; PWIDTH_STORE_NFA:
; 	.byte	$87,"PWIDTH",$A1
; 	.word	SINIT_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: PWIDTH@ [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- n1 )
; ; Manual: Returns the PULSE width register value for voice #1, in the range 0
; ; to 4095. See S!
; PWIDTH_FETCH_NFA:
; 	.byte	$87,"PWIDTH",$C0
; 	.word	PWIDTH_STORE_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: FREQ! [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( n1 --- )
; ; Manual: Sets the frequency value for the currently selected voice. This is
; ; the compliment of FREQ@. n1 is in the range 0 to 65,535. See S!
; FREQ_STORE_NFA:
; 	.byte	$85,"FREQ",$A1
; 	.word	PWIDTH_FETCH_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: FREQ@ [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- n1 )
; ; Manual: Returns the frequency value from the currently selected voice. This
; ; is the compliment of FREQ! See S!
; FREQ_FETCH_NFA:
; 	.byte	$85,"FREQ",$C0
; 	.word	FREQ_STORE_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: TRIANGLE [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- )
; ; Manual: Sets the currently selected voice to generate a triangle wave. This
; ; is one of several types of waveforms that can be generated. See also
; ; SQUARE, NOISE, SAWTOOTH. See S!
; TRIANGLE_NFA:
; 	.byte	$88,"TRIANGL",$C5
; 	.word	FREQ_FETCH_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: GATE1 [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual: Enables the currently selected voice, that is, turns it ON. See S!
; GATE1_NFA:
; 	.byte	$85,"GATE",$B1
; 	.word	TRIANGLE_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: GATE0 [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- )
; ; Manual: Disables the currently selected voice, that is, turns it OFF. See
; ; S!.
; GATE0_NFA:
; 	.byte	$85,"GATE",$B0
; 	.word	GATE1_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: SAWTOOTH [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- )
; ; Manual: Sets the current voice to generate a SAWTOOTH wave form. One of a
; ; group of four words, which select the basic waveform for a selected voice.
; ; See also NOISE, SQUARE, TRIANGLE. See S!
; SAWTOOTH_NFA:
; 	.byte	$88,"SAWTOOT",$C8
; 	.word	GATE0_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: SYNC1 [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- )
; ; Manual: When this word is executed, oscillator #1 will be hard synchronized
; ; with voice #3. See S!
; SYNC1_NFA:
; 	.byte	$85,"SYNC",$B1
; 	.word	SAWTOOTH_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: SYNC0 [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- )
; ; Manual: When this word is executed, oscillator #1 is not hard synchronized
; ; with voice #3, and each oscillator can be programmed independently. This is
; ; the normal condition. See S!
; SYNC0_NFA:
; 	.byte	$85,"SYNC",$B0
; 	.word	SYNC1_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: SQUARE [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- )
; ; Manual: Sets the currently selected voice to generate a square wave. This
; ; is one of several types of waveforms that can be generated. See also
; ; TRIANGLE, SAWTOOTH, and NOISE. See S1
; SQUARE_NFA:
; 	.byte	$86,"SQUAR",$C5
; 	.word	SYNC0_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: RING1 [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Implementation: Enable ring modulation in the current voice shadow
; ; (control-register bit 2). S! commits it to hardware.
; RING1_NFA:
; 	.byte	$85,"RING",$B1
; 	.word	SQUARE_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: RING0 [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Implementation: Disable ring modulation in the current voice shadow
; ; (control-register bit 2). S! commits it to hardware.
; RING0_NFA:
; 	.byte	$85,"RING",$B0
; 	.word	RING1_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: NOISE [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- )
; ; Manual: Sets the currently selected voice to generate noise. This is 136
; ; one of four basic signals the SID chip can generate. See also TRIANGLE,
; ; SAWTOOTH, SQUARE. See S!
; NOISE_NFA:
; 	.byte	$85,"NOIS",$C5
; 	.word	RING0_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: TEST1 [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- )
; ; Manual: A sound control word, which can be used to synchronize oscillator
; ; #1 to external events. If this word is executed, oscillator #1 will stop
; ; output, until a TESTO is executed. Normally used for testing. See S!
; TEST1_NFA:
; 	.byte	$85,"TEST",$B1
; 	.word	NOISE_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: TEST0 [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- )
; ; Manual: A sound control word, which can be used to synchronize oscillator
; ; #1 to external events. If this word is executed, oscillator #1 will be
; ; enabled-the normal condition. Normally used for testing. See S!
; TEST0_NFA:
; 	.byte	$85,"TEST",$B0
; 	.word	TEST1_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: VOICE1 [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- )
; ; Manual: Sets the current voice to be manipulated by the sound control words
; ; to VOICE1, by setting the value of the CURVOICE system variable to the
; ; offset into the SID sound register area. See S!
; VOICE1_NFA:
; 	.byte	$86,"VOICE",$B1
; 	.word	TEST0_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: VOICE2 [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- )
; ; Manual: Sets the current voice to be manipulated by the sound control words
; ; to VOICE2, by setting the value of the CURVOICE system variable to the
; ; offset into the SID sound register area. See S!
; VOICE2_NFA:
; 	.byte	$86,"VOICE",$B2
; 	.word	VOICE1_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: VOICE3 [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- )
; ; Manual: Sets the current voice to be manipulated by the sound control words
; ; to VOICE3, by setting the value of the CURVOICE system variable to the
; ; offset into the SID sound register area. See S!
; VOICE3_NFA:
; 	.byte	$86,"VOICE",$B3
; 	.word	VOICE2_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: REGSET [SYSTEM].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual: A low level primitive, used by the sound system. Not a user word.
; REGSET_NFA:
; 	.byte	$86,"REGSE",$D4
; 	.word	WFORM_NFA	; LFA: previous name field in this vocabulary chain
; REGSET:
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: REGREAD [SYSTEM].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual: A low level primitive, used by the sound system. Not a user word.
; ; 140
; REGRED_NFA:
; 	.byte	$87,"REGREA",$C4
; 	.word	REGSET_NFA	; LFA: previous name field in this vocabulary chain
; REGRED:
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: ATTACK! [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( n1 --- )
; ; Manual: Sets the attack register value for the currently selected voice, in
; ; the range 0 to 15. See S!
; ATTACK_STORE_NFA:
; 	.byte	$87,"ATTACK",$A1
; 	.word	VOICE3_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: ATTACK@ [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- n1 )
; ; Manual: Returns the attack register value for the currently selected voice,
; ; in the range from 0 to 15. See S!
; ATTACK_FETCH_NFA:
; 	.byte	$87,"ATTACK",$C0
; 	.word	ATTACK_STORE_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: DECAY! [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( n1 --- )
; ; Manual: Set the decay register value for the currently selected voice in
; ; the SID chip to value n1, in the range 0 to 15. See S!
; DECAY_STORE_NFA:
; 	.byte	$86,"DECAY",$A1
; 	.word	ATTACK_FETCH_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: DECAY@ [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- n1 )
; ; Manual: Return the decay register value for the currently selected voice,
; ; in the range 0 to 15, See S!
; DECAY_FETCH_NFA:
; 	.byte	$86,"DECAY",$C0
; 	.word	DECAY_STORE_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: SUSTAIN! [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( n1 --- )
; ; Manual: Sets the sustain register value for the currently selected voice.
; ; See S!
; SUSTAIN_STORE_NFA:
; 	.byte	$88,"SUSTAIN",$A1
; 	.word	DECAY_FETCH_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: SUSTAIN@ [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- n1 )
; ; Manual: Returns the value of the sustain register for the currently
; ; selected voice. See S!
; SUSTAIN_FETCH_NFA:
; 	.byte	$88,"SUSTAIN",$C0
; 	.word	SUSTAIN_STORE_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: RELEASE! [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( n1 --- )
; ; Manual: Sets the release register value for the currently selected voice.
; ; See S!
; RELEASE_STORE_NFA:
; 	.byte	$88,"RELEASE",$A1
; 	.word	SUSTAIN_FETCH_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: RELEASE@ [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- n1 )
; ; Manual: Reads the release register value for the currently selected voice.
; ; See S!
; RELEASE_FETCH_NFA:
; 	.byte	$88,"RELEASE",$C0
; 	.word	RELEASE_STORE_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: FILTER! [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( n1 --- )
; ; Manual: Sets the filter center/cutoff frequency to the value specified as
; ; n1, in the range 0 to 2047. See S!
; FILTER_STORE_NFA:
; 	.byte	$87,"FILTER",$A1
; 	.word	RELEASE_FETCH_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: RESONANCE! [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( n1 --- )
; ; Manual: Sets the RESONANCE register value for the filter, lower values
; ; reduce filter effect, and higher values increase filter effect. N1 is in
; ; the range 0 to 15.
; RESONANCE_STORE_NFA:
; 	.byte	$8A,"RESONANCE",$A1
; 	.word	FILTER_STORE_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: RESONANCE@ [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- n1 )
; ; Manual: Returns the current value of the filter, RESONANCE register
; ; setting, in the range 0 to 15.
; RESONANCE_FETCH_NFA:
; 	.byte	$8A,"RESONANCE",$C0
; 	.word	RESONANCE_STORE_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: FSELECT! [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( n1 --- )
; ; Manual: Sets the filter select register, to cause the filter to be
; ; effective on the voices specified by the bits of value n1. The bit values
; ; for each voice are as follows: voice#1=01, voice#2=02, voice#3=04,
; ; external=08 Any or all of these values can be ORed together to create the
; ; value n1 passed to FSELECT! See S!.
; FSELECT_STORE_NFA:
; 	.byte	$88,"FSELECT",$A1
; 	.word	RESONANCE_FETCH_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: FSELECT@ [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- n1 )
; ; Manual: Returns the filter select register, which holds the value n1 ---
; ; the voices specified to be filtered. The bit values for each voice are as
; ; follows: voice#l=01, voice#2=02, voice#3=04, external=08 These values can
; ; be 0Red together to create n1. See S!.
; FSELECT_FETCH_NFA:
; 	.byte	$88,"FSELECT",$C0
; 	.word	FSELECT_STORE_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: FMODE! [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( n1 --- )
; ; Manual: Sets the filter mode register value to select the type of filtering
; ; desired. Each of the low 4 bits of the value n1 are a type of filter action
; ; as follows: 128 low-pass=01, band-pass=02, high-pass=04 and voice #3 off=08
; ; Any of the first three filter types can be selected, or 0Red together, to
; ; form a more complex filter action. The last bit, VOICE #3 OFF, is used to
; ; remove voice #3 from the output without turning it off internally. This
; ; allows oscillator #3 to be used to modulate the other voices, without its
; ; output appearing directly in the output of the sound chip. See S!
; FMODE_STORE_NFA:
; 	.byte	$86,"FMODE",$A1
; 	.word	FSELECT_FETCH_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: FMODE@ [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- n1 )
; ; Manual: Returns the filter mode register value, indicating the type of
; ; filter currently selected. See FMODE! for further information about the
; ; value returned as n1. See S!
; FMODE_FETCH_NFA:
; 	.byte	$86,"FMODE",$C0
; 	.word	FMODE_STORE_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: VOLUME! [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( n1 --- )
; ; Manual: Sets the current value of the volume register to value n1 in the
; ; range 0 to 15 in the SID sound generator chip. See S!
; VOLUME_STORE_NFA:
; 	.byte	$87,"VOLUME",$A1
; 	.word	FMODE_FETCH_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: VOLUME@ [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- n1 )
; ; Manual: Fetches the current value of the volume register in the SID sound
; ; generator chip. See S!
; VOLUME_FETCH_NFA:
; 	.byte	$87,"VOLUME",$C0
; 	.word	VOLUME_STORE_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: OSC3@ [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- n1 )
; ; Manual: Returns the output of the waveform for oscillator #3 as a number n1
; ; in the range 0 to 255.
; OSC3_FETCH_NFA:
; 	.byte	$85,"OSC3",$C0
; 	.word	VOLUME_FETCH_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: ENV3@ [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- n1 )
; ; Manual: Returns the value of the oscillator #3 ENVELOPE generator, in the
; ; range 0 to 255.
; ENV3_FETCH_NFA:
; 	.byte	$85,"ENV3",$C0
; 	.word	OSC3_FETCH_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: SPOBJ [SYSTEM].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- a1 )
; ; Manual: This is a system variable used In the creation of a sprite data
; ; definition, after a sprite edit has been completed. Not a user word.
; SPOBJ_NFA:
; 	.byte	$85,"SPOB",$CA
; 	.word	REGRED_NFA	; LFA: previous name field in this vocabulary chain
; SPOBJ:
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: SPINDX [SYSTEM].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- a1 )
; ; Manual: This is a system variable used in the creation of a sprite data
; ; definition after a sprite edit has been completed. Not a user word.
; SPINDX_NFA:
; 	.byte	$86,"SPIND",$D8
; 	.word	SPOBJ_NFA	; LFA: previous name field in this vocabulary chain
; SPINDX:
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: SPBYT [SYSTEM].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- a1 )
; ; Manual: This is a system variable used in the creation of a sprite data
; ; definition after a sprite edit has been completed. Not a user word.
; SPBYT_NFA:
; 	.byte	$85,"SPBY",$D4
; 	.word	SPINDX_NFA	; LFA: previous name field in this vocabulary chain
; SPBYT:
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: SCPTR [SYSTEM].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- a1 )
; ; Manual: A system variable, used in the creation of a sprite definition. Not
; ; a user word.
; SCPTR_NFA:
; 	.byte	$85,"SCPT",$D2
; 	.word	SPBYT_NFA	; LFA: previous name field in this vocabulary chain
; SCPTR:
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: SPBIT [SYSTEM].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- )
; ; Manual: A system sprite word used to read bytes from the screen in the
; ; process of building a sprite data definition. Not a user word.
; SPBIT_NFA:
; 	.byte	$85,"SPBI",$D4
; 	.word	SCPTR_NFA	; LFA: previous name field in this vocabulary chain
; ; Sprite conversion worker: use SPOBJ/SPINDX/SPBYT/SCPTR user variables to
; ; accumulate bitmap data. Sprite storage has three bytes per row and 21 rows
; ; (63 payload bytes per 64-byte sprite slot).
; SPBIT:
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: SPGET [SYSTEM].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- )
; ; Manual: A system sprite word used to read bytes from the screen in the
; ; process of building a sprite data definition. Not a user word.
; SPGET_NFA:
; 	.byte	$85,"SPGE",$D4
; 	.word	SPBIT_NFA	; LFA: previous name field in this vocabulary chain
; SPGET:
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: SPRITE [SYSTEM].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- )
; ; Manual: Builds the sprite data definition from the characters on the 144
; ; screen In the sprite definition area within the sprite editor border. This
; ; word is automatically executed by the sprite editor when the <RETURN> key
; ; is pressed upon completion of a sprite edit.
; SPRITE_NFA:
; 	.byte	$86,"SPRIT",$C5
; 	.word	SPGET_NFA	; LFA: previous name field in this vocabulary chain
; SPRITE:
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: MASK [SYSTEM].
; Manual stack: ( --- a1 )
; Manual: An array, which contains the values used when converting from bit
; number to the mask value for that bit, used by ORMASK and ANDMASK. This
; array contains 8 values ranging from 01 to 80, as follows: 01, 02, 04, 08,
; 10, 20, 40, 80.
MASK_NFA:
	.byte	$84,"MAS",$CB
;	.word	SPRITE_NFA	; LFA: previous name field in this vocabulary chain
	.word	PCONT_NFA	; LFA: previous name field in this vocabulary chain
MASK:
	.word	DOVAR	; CFA: variable; push the parameter-field address
	.byte	$01,$02,$04,$08
	.byte	$10,$20,$40,$80

;	ORMASK

; ---------------------------------------------------------------------------
; Dictionary: ORMASK [SYSTEM].
; Manual stack: ( n1/a1 --- )
; Manual: Sets the bit specified by bit number n1 in the byte contained in
; address a1. Example: "4 500 ORMASK" OR the contents of address 500 with
; 00010000 binary, and replace the result in address 500. Used to manipulate
; the bits of the various sprite registers.
ORMASK_NFA:
	.byte	$86,"ORMAS",$CB
	.word	MASK_NFA	; LFA: previous name field in this vocabulary chain
ORMASK:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	SWAP
	.word	MASK
	.word	PLUS
	.word	CAT
	.word	OVER
	.word	CAT
	.word	ORR
	.word	SWAP
	.word	CSTOR
	.word	SEMIS	; Return to caller thread

;	ANDMASK

; ---------------------------------------------------------------------------
; Dictionary: ANDMASK [SYSTEM].
; Manual stack: ( n1/a1 --- )
; Manual: This is a SPRITE system primitive, which takes a bit number n1 in
; the range 0 to 7, and clears that bit in the byte contained at address a1.
; Example "4 500 ANDMASK" resets sprite register bit 4 and the value in
; address 500 with 1110 1111 binary, and stores the value back in location
; 500. This word is useful for manipulating the various sprite register bits.
ANDMSK_NFA:
	.byte	$87,"ANDMAS",$CB
	.word	ORMASK_NFA	; LFA: previous name field in this vocabulary chain
ANDMSK:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	SWAP
	.word	MASK
	.word	PLUS
	.word	CAT
	.word	LIT,$FF
	.word	XORR
	.word	OVER
	.word	CAT
	.word	ANDD
	.word	SWAP
	.word	CSTOR
	.word	SEMIS	; Return to caller thread

;	MASK?

; ---------------------------------------------------------------------------
; Dictionary: MASK? [SYSTEM].
; Manual stack: ( n1/a1/f1 --- )
; Manual: This word allows you to specify a boolean flag to select which of
; the operations "ORMASK" and "ANDMASK" are done. If f1 is zero (0), an
; "ANDMASK" is performed. and if fl is non-zero, an "ORMASK" is done. The
; additional parameters n1 and a1, are passed on to the appropriate function.
; Used by the XPAND word in determining the expansion of a particular sprite.
MASKQ_NFA:
	.byte	$85,"MASK",$BF
	.word	ANDMSK_NFA	; LFA: previous name field in this vocabulary chain
MASKQ:
	.word	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.word	ZBRAN,8	; Pop flag; if zero branch to $BC1E (offset +8 from operand cell)
	.word	ORMASK
	.word	BRAN,4	; Jump to $BC20 (offset +4 from operand cell)
	.word	ANDMSK
	.word	SEMIS	; Return to caller thread

;	COLOR

; ; ---------------------------------------------------------------------------
; ; Dictionary: COLOR [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( n1/n2 --- )
; ; Manual: Sets the color n1 for sprite number n2. The color numbers are the
; ; same as shown on page 139 of the Commodore 64 Users Manual. 117
; COLOR_NFA:
; 	.byte	$85,"COLO",$D2
; 	.word	ENV3_FETCH_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: SHOW [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( n1 --- )
; ; Manual: Turns on the sprite specified by n1 and makes it visible on the
; ; screen. N1 is in the range 0 to 7.
; SHOW_NFA:
; 	.byte	$84,"SHO",$D7
; 	.word	COLOR_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: HIDE [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( n1 --- )
; ; Manual: Causes the sprite specified by n1 to be hidden from the screen
; ; view. See also SHOW.
; HIDE_NFA:
; 	.byte	$84,"HID",$C5
; 	.word	SHOW_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: XY [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( n1/n2/n3 --- )
; ; Manual: Moves sprite n3 to screen position x=n1 and y=n2. This is the fast
; ; version which only has access to the first 255 X locations on the screen.
; ; Before XY can be used, the word CXY must have been used at least once to
; ; initialize the most significant bit of the sprite position. n1 is in the
; ; range 0 to 255, and n2 is in the range 0 to 159. n3 is the sprite number
; ; and must be in the range 0 to 7.
; XY_NFA:
; 	.byte	$82,"X",$D9
; 	.word	HIDE_NFA	; LFA: previous name field in this vocabulary chain
; XY:
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: CXY [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( n1/n2/n3 --- )
; ; Manual: This is the sprite position control word, which allows any sprite
; ; n3 to be placed at any address on the screen at n1=x and n2=y. This slower
; ; version of XY allows full screen placement of a sprite. See XY.
; CXY_NFA:
; 	.byte	$83,"CX",$D9
; 	.word	XY_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: MULTI [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( n1 --- )
; ; Manual: Selects multi-color mode for sprite n1. Don't forget to set MCLR1
; ; and MCLR2 first.
; MULTI_NFA:
; 	.byte	$85,"MULT",$C9
; 	.word	CXY_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: HIRES [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( n1 --- )
; ; Manual: Causes the sprite specified by n1 to be set in high resolution
; ; mode. This is the default mode, where each sprite has a foreground and a
; ; background color. See also MULTI, for use of the multi-color sprite mode.
; ; Pronounced "hi rez."
; HIRES_NFA:
; 	.byte	$85,"HIRE",$D3
; 	.word	MULTI_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: XPAND [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( f1/f2/n1 --- )
; ; Manual: A sprite control word, which allows sprite n1 to be expanded in
; ; either vertical or horizontal directions, or both. The boolean flag f1 is
; ; the X direction expand flag, and flag f2 is the Y direction expand flag.
; ; Example "1 0 3 XPAND" will expand sprite 3 in the X direction, but not the
; ; Y direction.
; XPAND_NFA:
; 	.byte	$85,"XPAN",$C4
; 	.word	HIRES_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: MCLR1 [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Implementation: ( color -- ) Set the VIC-II shared sprite multicolor-1
; ; register.
; MCLR1_NFA:
; 	.byte	$85,"MCLR",$B1
; 	.word	XPAND_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: MCLR2 [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Implementation: ( color -- ) Set the VIC-II shared sprite multicolor-2
; ; register.
; MCLR2_NFA:
; 	.byte	$85,"MCLR",$B2
; 	.word	MCLR1_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: SB [SYSTEM].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Stack (from code): ( -- block-number )
; ; Original C64 manual: A system constant, #30 hex in this system, which specifies the 64
; ; byte block where the sprite data definitions start; $40 hex=64 decimal, and
; ; $30 times $40 is $0C00, the start of the sprite definition area.
; SB_NFA:
; 	.byte	$82,"S",$C2
; 	.word	MASKQ_NFA	; LFA: previous name field in this vocabulary chain
; SB:
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: SBLK [SYSTEM].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- a1 )
; ; Manual: This is a system constant which returns the address a1 of an array
; ; which contains the sprite data block pointer bytes. This array is located
; ; at $07F8, just beyond the end of the display screen.
; SBLK_NFA:
; 	.byte	$84,"SBL",$CB
; 	.word	SB_NFA	; LFA: previous name field in this vocabulary chain
; SBLK:
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: SPBASE [SYSTEM].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- )
; ; Manual: Initializes the array SBLK to contain the proper pointers to the
; ; sprite data definition areas. Automatically executed when a new sprite is
; ; defined, or when a sprite is read from mass storage.
; SPBASE_NFA:
; 	.byte	$86,"SPBAS",$C5
; 	.word	SBLK_NFA	; LFA: previous name field in this vocabulary chain
; ; Initialize the eight default-screen sprite pointers at $07F8 to consecutive
; ; 64-byte sprite blocks beginning at SB. These pointers depend on the VIC
; ; screen/bank configuration.
; SPBASE:
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: CUR [SYSTEM].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( n1/n2 --- )
; ; Manual: This is another sprite system primitive, but one which might be
; ; useful to some people. It allows you to specify the location on the screen
; ; where the cursor will be 119 positioned, by performing the system call
; ; which positions the cursor. The parameters are n1 = the X position, and n2
; ; = the Y position for the new cursor location.
; CUR_NFA:
; 	.byte	$83,"CU",$D2
; 	.word	SPBASE_NFA	; LFA: previous name field in this vocabulary chain
; CUR:
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: VDG [SYSTEM].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( n1 --- )
; ; Manual: A system sprite editor primitive used to draw a vertical line on
; ; the screen at column n1. Not a user word.
; VDG_NFA:
; 	.byte	$83,"VD",$C7
; 	.word	CUR_NFA	; LFA: previous name field in this vocabulary chain
; VDG:
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: BDG [SYSTEM].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( n1 --- )
; ; Manual: This is another system sprite primitive. It draws a horizontal line
; ; on the screen as a line specified by n1, 26 characters long, to make the
; ; top and bottom of the borders of the sprite editor. This is not a user
; ; word.
; BDG_NFA:
; 	.byte	$83,"BD",$C7
; 	.word	VDG_NFA	; LFA: previous name field in this vocabulary chain
; BDG:
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: -SPOBJ [SYSTEM].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( n1 --- n1/a1 )
; ; Manual: Converts the sprite number n1 to the address a1 of the data
; ; definition area for that sprite. Also leaves a copy of the sprite number on
; ; the stack as n1. This is a low level sprite manipulation word, normally
; ; used only by the system.
; DSPOBJ_NFA:
; 	.byte	$86,"-SPOB",$CA
; 	.word	BDG_NFA	; LFA: previous name field in this vocabulary chain
; DSPOBJ:
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: RBYT [SYSTEM].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( --- )
; ; Manual: A system primitive, used to read a byte of the sprite currently
; ; selected and about to be edited. A "*" is shown on the screen for each bit
; ; of the byte read, which was non zero. Probably not a useful user word.
; RBYT_NFA:
; 	.byte	$84,"RBY",$D4
; 	.word	DSPOBJ_NFA	; LFA: previous name field in this vocabulary chain
; RBYT:
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: SPEDIT [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( n1 --- )
; ; Manual: Enters the sprite edit mode with sprite n1. Shows the current form
; ; of the selected sprite. SPEDIT is terminated by pressing <RETURN>.
; SPEDIT_NFA:
; 	.byte	$86,"SPEDI",$D4
; 	.word	MCLR2_NFA	; LFA: previous name field in this vocabulary chain
; ; Interactive sprite editor: display the editing guide, initialize
; ; sprite/cursor state and key-repeat behavior, process 21 rows of three
; ; bytes, then wait for RETURN and rebuild the sprite data.
; SPEDIT:
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: NEWSPRITE [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( n1 --- )
; ; Manual: Enters the sprite editor, with sprite n1 cleared. You now use the
; ; cursor movement keys and the star (*) symbol to draw your sprite on the
; ; screen within the box shown. Pairs of symbols in the form "**", "_*", "*_"
; ; or "__" are used to select the specific color in multi-color mode.
; NEWSPRITE_NFA:
; 	.byte	$89,"NEWSPRIT",$C5
; 	.word	SPEDIT_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: SCRN? [SYSTEM].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( n1 --- n2 )
; ; Manual: A system primitive, which converts the sprite number n1 to the mass
; ; storage screen which contains, or will contain, the data statements for
; ; that sprite. Each sprite is assigned a particular location on a mass
; ; storage screen. Eight (8) sprites can be stored in two screens. Sprites 0
; ; to 3 are always located in screen one (1), and sprites 4 through 7 are
; ; always located in screen two (2). Each sprite is 142 assigned four (4)
; ; lines of its first screen to hold the ASCII decimal values associated with
; ; that sprite. Sprite 0 is located on line 0 through 3 of screen 1, sprite 1
; ; is located on fines 4 through 7 of screen 1, and so on. See also SPWRITE
; ; and SPREAD.
; SCRNQ_NFA:
; 	.byte	$85,"SCRN",$BF
; 	.word	RBYT_NFA	; LFA: previous name field in this vocabulary chain
; ; Split a sprite index (clamped to at most 7) using /MOD by four: return the
; ; slot within a screen and screen number 1 or 2. SPWRITE/SPREAD use 256 text
; ; bytes per serialized sprite.
; SCRNQ:
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: SPWRITE [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( n1 --- )
; ; Manual: Writes sprite n1 out of the FORTH screen, either screen 1 or 2,
; ; from the sprite data area where it may be written to or read from. Sprites
; ; 0 to 3 are on screen 1, and sprites 4 through 7 are on screen 2. Each
; ; sprite has four lines, and its data is maintained in ASCII decimal in the
; ; screen. See SPREAD.
; SPWRITE_NFA:
; 	.byte	$87,"SPWRIT",$C5
; 	.word	NEWSPRITE_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ; ---------------------------------------------------------------------------
; ; Dictionary: SPREAD [FORTH].
; ; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; ; Original C64 manual stack: ( n1 --- )
; ; Manual: Reads sprite n1 from the FORTH screen 1 or 2, into the sprite data
; ; area for the sprite specified. Each sprite has a designated area where it
; ; may be written to or read from. Sprites 0 to 3 are on screen 1, and sprites
; ; 4 through 7 are on screen 2. Each sprite has four lines, and its data is
; ; maintained in ASCII decimal in the screen. See SPWRITE.
; SPREAD_NFA:
; 	.byte	$86,"SPREA",$C4
; 	.word	SPWRITE_NFA	; LFA: previous name field in this vocabulary chain
; 	.word	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
.include "forth_words.inc"

.segment "VECTORS"
	.word	shell_nmi		; NMI vector address
	.word	reset		; RESET vector address
	.word	shell_irq		; IRQ/BRK vector address
