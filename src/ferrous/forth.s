; ============================================================================
; FORTH for IMNOTWOPR
; 
; Based/Inspired on/by 64FORTH By Tom Zimmer
; ============================================================================

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

.segment "PROGRAM_CODE"

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
L8000:
	.WORD	L8019			; COLD BOOT
	.WORD	L8009			; WARM BOOT
	.BYTE	$C3,$C2,$CD,$38,$30	; CARTRIDGE ID

L8009:
    jmp shell_abort

reset:
L8019:
    jmp shell_cold

; Compatibility alias for monitor users; the shell now waits for serial input.
main = serial_wait_key

; ----------------------------------------------------------------------------
; ORIGIN / INITIAL USER IMAGE. +ORIGIN indexes this ROM table. The first 12
; bytes are reserved; ORIG+12 starts the user initialization image. L9436
; copies 22 bytes for COLD or 14 for WARM to UP. These are startup values,
; not live variables.
ORIG:
	.WORD	0
	.WORD	0
	.WORD	0
	.WORD	0
	.WORD	0
	.WORD	0

; ----------------------------------------------------------------------------
; BOOTUP VARIABLES

	.WORD	$87B		; TOP WORD
	.WORD	0		; 
L8047:
	.WORD	USRINI		; UP
	.WORD	TOS		; TOP OF STACK
	.WORD	$1FF		; TOP OF RETURN STACK
	.WORD	TIBINI		; TIB
	.WORD	$1F		; WIDTH
	.WORD	0		; 
	.WORD	DICT_START	; FENCE
	.WORD	DICT_START	; DP
	.WORD	$88C		; VOC-LINK


; ----------------------------------------------------------------------------
; Dictionary: VWORDS [FORTH].
; Manual stack: ( --- a1)
; Manual: This word returns the address all of the beginning of the initial
; value vector table in ROM.  See the section VECTORED WORDS for further
; information.
L8059:
    .byte   $86,"VWORD",$D3
    .word   0                   ; LFA: previous name field in this vocabulary chain
; DEFAULT VECTOR TABLE. The first twelve cells are CFAs, not machine-code
; entry addresses. They are followed by the capture-table pointer and initial
; file/device numbers. VRESET copies 28 bytes to UP+$32: the twelve
; I/O/compiler vectors, CTBL, and F#. The last value (D#) is outside that
; copy. The listing has comma at offset 20 and C-comma at 18; use these
; values rather than the reversed manual table.
VWORDS:
	.WORD	DOVAR	    ; CFA: variable; push the parameter-field address
	.WORD	PKEY		; 0
	.WORD	PEMIT		; 2
	.WORD	PQTER		; 4
	.WORD	PCRR		; 6
	.WORD	PCREAT		; 8
	.WORD	PNUMBE		; 10
	.WORD	PERROR		; 12
	.WORD	PDOT		; 14
	.WORD	PDFIND		; 16
	.WORD	PCCOM		; 18
	.WORD	PCOMMA		; 20
	.WORD	PRSLW		; 22
	.WORD	L80D1		; 24
	.WORD	1		    ; 26
	.WORD	1		    ; 28

; KEY CAPTURE TABLE. Repeating PETSCII byte / Forth CFA pairs, terminated by
; a zero byte. PKEY scans CTBL, executes a matching action and retries when
; it returns zero. $94 appears twice; the earlier matching action can consume
; it. Codes $85/$86/$87/$88 are F1/F3/F5/F7; $89/$8A/$8B/$8C are F2/F4/F6/F8.
L8082:
	.BYTE	$94		    ; 
	.WORD	L9EBF

	.BYTE	$85		    ; F1
	.WORD	LA048

	.BYTE	$86		    ; F3
	.WORD	LA051

	.BYTE	$87		    ; F5
	.WORD	LA05B

	.BYTE	$1D		    ; RIGHT
	.WORD	LA065

	.BYTE	$9D		    ; LEFT
	.WORD	LA06D

	.BYTE	$11		    ; DOWN
	.WORD	LA077

	.BYTE	$91		    ; UP
	.WORD	LA07F

	.BYTE	$13		    ; CTL-S
	.WORD	TOP

	.BYTE	$89		    ; F2
	.WORD	NN

	.BYTE	$8A		    ; F4
	.WORD	BB

	.BYTE	$88		    ; F7
	.WORD	PFF

	.BYTE	$8C		    ; F8
	.WORD	LA089

	.BYTE	$94		    ; 
	.WORD	L9F35

	.BYTE	$8B		    ; F6
	.WORD	LA091

	.BYTE	$B0		    ; CBM-A
	.WORD	LA051

	.BYTE	$AE		    ; CBM-S
	.WORD	LA06D

	.BYTE	$AC		    ; CBM-D
	.WORD	LA065

	.BYTE	$BB		    ; CBM-B
	.WORD	LA048

	.BYTE	$B1		    ; CBM-E
	.WORD	LA07F

	.BYTE	$B2		    ; CBM-R
	.WORD	BB

	.BYTE	$BD		    ; CBM-X
	.WORD	LA077

	.BYTE	$BC		    ; CBM-C
	.WORD	NN

	.BYTE	$A5		    ; CBM-G
	.WORD	LA0AB

	.BYTE	$AD		    ; CBM-Z
	.WORD	LA0A1

	.BYTE	$B7		    ; CBM-Y
	.WORD	LA099

	.BYTE	0

; Default capture table: RETURN ($8D, shifted RETURN) invokes the
; copyright-message thread. Zero ends the table.
L80D1:
	.BYTE	$8D
	.WORD	L80D5
	.BYTE	0

; Anonymous colon definition used by the default key-capture table. PDOTQ
; consumes the following length byte and that many bytes, including any bytes
; which also resemble threaded code.
L80D5:
	.WORD	DOCOL
	.WORD	CR
	.WORD	PDOTQ	; Print counted inline text; resume after its payload
	.BYTE	18
	.BYTE	"(C)1983 TOM ZIMMER"
	.WORD	CR
	.WORD	SEMIS	; Return to caller thread

; ============================================================================
; NATIVE CORE AND THREADED EXECUTION
; ============================================================================

; ----------------------------------------------------------------------------
; Dictionary: (MATCH) [FORTH].
; Manual stack: (a1/a2/n1 --- f1 )
; Manual: An assembly language MATCH primitive. Given the addresses of
; strings of characters (a1 and a2), and a match length of characters (n1),
; returns boolean f1 as true if the strings are the same character sequence.
; Otherwise, returns a boolean false.
L80F2:
	.BYTE	$87,"(MATCH",$A9
	.WORD	L8059	; LFA: previous name field in this vocabulary chain
; IMPLEMENTATION ( a1 a2 n -- flag ). Only the low byte of n is used. Compare
; backwards through n bytes using XSAVE/XSAVE+1 and NXTMP/NXTMP+1 as
; pointers. A zero length returns false in this implementation. Replace a1
; with 0 or 1 and discard a2/n.
PMATCH:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 3
	LDY	0,X
	BEQ	L8123
	LDA	2,X
	STA	NXTMP
	LDA	3,X
	STA	NXTMP+1
	LDA	4,X
	STA	XSAVE
	LDA	5,X
	STA	NXTMP-1
; Compare one byte from each string, working toward offset zero.
L8112:
	DEY
	LDA	(NXTMP),Y
	CMP	(XSAVE),Y
	BNE	L8123
	CPY	#0
	BNE	L8112
	LDA	#1
	STA	4,X
	BNE	L8128
; Mismatch or zero length: return false.
L8123:
	LDA	#0
	TAY
	STA	4,X
L8128:
	TYA
	STA	5,X
	JMP	POPTWO

; ----------------------------------------------------------------------------
; Dictionary: LIT [FORTH].
; Manual stack: ( --- n )
; Manual: Within a colon-definition, LIT is automatically compiled before
; each 16 bit literal number encountered in input text. Later execution of
; LIT causes the contents of the next dictionary address to be pushed to the
; stack.
L812E:
	.BYTE	$83,"LI",$D4
	.WORD	L80F2	; LFA: previous name field in this vocabulary chain
; LIT ( -- cell ): read the two bytes following this token in the thread. IP
; already points at the literal, and Y=0 on entry. The low byte is staged on
; the hardware stack; A carries the high byte to PUSH.
LIT:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
	LDA	(IP),Y
	PHA
	INC	IP
	BNE	L813F
	INC	IP+1
L813F:
	LDA	(IP),Y
; Advance IP past the final literal byte; carry propagates across pages.
L8141:
	INC	IP
	BNE	PUSH
	INC	IP+1

; Shared tail: allocate a new 16-bit data-stack cell by decreasing X twice.
; Entry requires high byte in A and low byte on top of the hardware stack.
PUSH:
    cpx #STACK_BOTTOM+2
    bcs :+
    lda #27
    jmp shell_error
:
	DEX
	DEX

; Shared tail: replace the cell at X with A:PLA (high:low), then fall into
; NEXT. PUT does not allocate a cell.
PUT:
	STA	1,X
	PLA
	STA	0,X

; INNER INTERPRETER. Fetch the next CFA from [IP] into W, then fetch its
; machine-code address from [W] into NXTMP. Advance IP by two and JMP
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
	LDY	#1
	LDA	(IP),Y
	STA	W+1
	DEY
	LDA	(IP),Y
	STA	W
	LDA	(W),Y
	STA	NXTMP
	INY
	LDA	(W),Y
	STA	NXTMP+1
	DEY
	CLC
	LDA	IP
	ADC	#2	; Advance to the next thread cell before executing this one
	STA	IP
	BCC	L816E
	INC	IP+1
L816E:
	JMP	(NXTMP)	; Jump to the native entry, with Y=0 and W still the CFA

; ----------------------------------------------------------------------------
; Dictionary: CLIT [FORTH].
; Implementation: ( -- u ) Push an inline byte as a cell and advance IP by
; one.
L8171:
	.BYTE	$84,"CLI",$D4
	.WORD	L812E	; LFA: previous name field in this vocabulary chain
; CLIT ( -- byte ): like LIT, but consume one inline byte and push a
; zero-extended cell. Threads need not be word-aligned; do not insert
; alignment padding.
CLIT:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
	LDA	(IP),Y
	PHA
	TYA
	BEQ	L8141

; Native helper, entered with A=number of stack cells and Y=0. Copy 2*A bytes
; from the data stack into N upward, advancing X to consume them. N-1 is the
; byte count; Y is restored to zero. The topmost input becomes N/N+1.
SETUP:
	ASL	A
	STA	N-1
L8183:
	LDA	0,X
	STA	N,Y
	INX
	INY
	CPY	N-1
	BNE	L8183
	LDY	#0
	RTS

; ----------------------------------------------------------------------------
; Dictionary: EXECUTE [FORTH].
; Stack (from code): ( cfa -- )
; Manual: Executes the definition whose field address is on the stack. The
; code field address is also called the compilation address.
L8191:
	.BYTE	$87,"EXECUT",$C5
	.WORD	L8171	; LFA: previous name field in this vocabulary chain
; EXECUTE ( cfa -- ): pop a code-field address into W, fetch [W] and dispatch
; without advancing IP. The executed word returns to the already pending
; thread.
EXEC:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 1
	LDA	0,X
	STA	W
	LDA	1,X
	STA	W+1
	INX
	INX
	LDY	#0
; Dispatch W as a CFA; shared by EXECUTE and DOVEC.
L81A9:
	LDA	(W),Y
	STA	NXTMP
	INY
	LDA	(W),Y
	STA	NXTMP+1
	DEY
	JMP	(NXTMP)

; ----------------------------------------------------------------------------
; Dictionary: VECTOR [FORTH].
; Manual stack: ( n1 --- (text) )
; Manual: A defining word used in the form: n1 VECTOR (text) to create a word
; (text) which when executed will itself execute the contents of the n1
; vectored routine in the I/O table. User created vectors must start at value
; 30 decimal, and must not be higher than 50. The vector position in the I/O
; table must be initialized before the new vector is executed or a crash will
; result.
L81B6:
	.BYTE	$86,"VECTO",$D2
	.WORD	L8191	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	CONST
	.WORD	PSCOD
; Vector runtime: add the one-byte parameter to UP+$32, fetch the replacement
; CFA from that user-area slot, and use EXECUTE dispatch. The table therefore
; contains CFAs rather than raw 6502 entry points.
DOVEC:
	LDY	#2
	CLC
	LDA	(W),Y
	ADC	#$32
	ADC	UP
	STA	W
	LDA	#0
	TAY
	ADC	UP+1
	STA	W+1
	LDA	(W),Y
	PHA
	INY
	LDA	(W),Y
	DEY
	STA	W+1
	PLA
	STA	W
	JMP	L81A9

; ----------------------------------------------------------------------------
; Dictionary: BRANCH [FORTH].
; Manual: The run-time procedure to unconditionally branch. An in-line offset
; is added to the interpretive pointer to IP to branch ahead or back. BRANCH
; is compiled by ELSE, AGAIN, REPEAT.
L81E6:
	.BYTE	$86,"BRANC",$C8
	.WORD	L81B6	; LFA: previous name field in this vocabulary chain
; Runtime branch: add the signed 16-bit inline displacement to IP. The origin
; is the address of the displacement itself, not the following token.
; Arithmetic wraps modulo 65536.
BRAN:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
	CLC
	LDA	(IP),Y
	ADC	IP
	PHA
	INY
	LDA	(IP),Y
	ADC	IP+1
	STA	IP+1
	PLA
	STA	IP
	JMP	NEXT

; ----------------------------------------------------------------------------
; Dictionary: 0BRANCH [FORTH].
; Manual stack: ( f --- )
; Manual: The run-time procedure to branch conditionally. If f is false
; (zero), the following in-line parameter is added to the interpretive
; pointer to branch ahead or back. Compiled by IF, UNTIL, and WHILE.
L8204:
	.BYTE	$87,"0BRANC",$C8
	.WORD	L81E6	; LFA: previous name field in this vocabulary chain
; Runtime conditional branch: consume one flag. $FE,X/$FF,X deliberately wrap
; in zero page to read the cell just popped. Nonzero skips the two-byte
; displacement; zero shares BRANCH.
ZBRAN:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 1
	INX
	INX
	LDA	$FE,X
	ORA	$FF,X
	BEQ	BRAN+2

; Skip one inline 16-bit operand, carrying into IP+1, and resume NEXT.
BUMP:
	CLC
	LDA	IP
	ADC	#2
	STA	IP
	BCC	L8223
	INC	IP+1
L8223:
	JMP	NEXT

; ----------------------------------------------------------------------------
; Dictionary: (LOOP) [FORTH].
; Stack (from code): ( -- ) Update or remove the return-stack loop frame.
; Manual: The run-time procedure compiled by LOOP which increments the loop
; index and tests for loop completion. See LOOP.
L8226:
	.BYTE	$86,"(LOOP",$A9
	.WORD	L8204	; LFA: previous name field in this vocabulary chain
; Loop frame on hardware stack, relative to S: +1/+2=index, +3/+4=limit. Save
; data-stack X before TSX. Increment the index, compare to limit, then either
; take the inline backward branch or discard the four-byte frame and skip the
; offset.
PLOOP:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
	STX	XSAVE
	TSX
	INC	$101,X
	BNE	PL1
	INC	$102,X

; Compare limit-index-1; carry is deliberately clear before SBC.
PL1:
	CLC
	LDA	$103,X
	SBC	$101,X
	LDA	$104,X
	SBC	$102,X

; Use comparison sign to choose continuation; restore Forth X first.
PL2:
	LDX	XSAVE
	ASL	A
	BCC	BRAN+2
	PLA
	PLA
	PLA
	PLA
	JMP	BUMP

; ----------------------------------------------------------------------------
; Dictionary: (+LOOP) [FORTH].
; Manual stack: ( n --- )
; Manual: The run-time procedure compiled by +LOOP, which increments the loop
; index by n and tests for loop completion. See +LOOP.
L8255:
	.BYTE	$87,"(+LOOP",$A9
	.WORD	L8226	; LFA: previous name field in this vocabulary chain
; Consume the signed increment and add it to the hardware-stack loop index.
; Its sign chooses the comparison direction. PL2 restores data-stack X and
; shares loop termination with (LOOP).
PPLOO:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 1
	INX
	INX
	STX	XSAVE
	LDA	$FF,X
	PHA
	PHA
	LDA	$FE,X
	TSX
	INX
	INX
	CLC
	ADC	$101,X
	STA	$101,X
	PLA
	ADC	$102,X
	STA	$102,X
	PLA
	BPL	PL1
	CLC
	LDA	$101,X
	SBC	$103,X
	LDA	$102,X
	SBC	$104,X
	JMP	PL2

; ----------------------------------------------------------------------------
; Dictionary: (DO) [FORTH].
; Stack (from code): ( limit start -- ) Return stack: ( -- limit start ).
; Manual: The run-time procedure compiled by DO which moves the loop control
; parameters to the return stack. See DO.
L828F:
	.BYTE	$84,"(DO",$A9
	.WORD	L8255	; LFA: previous name field in this vocabulary chain
; (DO) ( limit start -- ): push limit high/low followed by index high/low
; onto the return stack. The index is nearest its top, so I can share the R
; fetch routine.
PDO:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 2
	LDA	3,X
	PHA
	LDA	2,X
	PHA
	LDA	1,X
	PHA
	LDA	0,X
	PHA

; Shared native tail: discard two data-stack cells (four bytes) by falling
; through POP.
POPTWO:
    REQUIRE_CELLS 2
	INX
	INX

; Shared native tail: discard one data-stack cell (two bytes), then dispatch
; NEXT.
POP:
    REQUIRE_CELLS 1
	INX
	INX
	JMP	NEXT

; ----------------------------------------------------------------------------
; Dictionary: I [FORTH].
; Manual stack: ( --- n )
; Manual: Copies the index of the current DO...LOOP counter to the
; computation stack.
L82AB:
	.BYTE	$81,$C9
	.WORD	L828F	; LFA: previous name field in this vocabulary chain
I:
	.WORD	R+2

; ----------------------------------------------------------------------------
; Dictionary: DIGIT [FORTH].
; Manual stack: ( c n1 --- n2 tf )
; Manual: ( c n1 --- ff ) Converts the ASCII character c (using base n1) to
; its binary equivalent n2, accompanied by a true flag. If the conversion is
; invalid, leaves only a false flag.
L82B1:
	.BYTE	$85,"DIGI",$D4
	.WORD	L82AB	; LFA: previous name field in this vocabulary chain
; Convert the low-byte character using decimal digits or uppercase letters.
; On success return the digit and true; on failure return false. This
; byte-oriented primitive compares against the low byte of the requested
; base.
DIGIT:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 2
	SEC
	LDA	2,X
	SBC	#'0'
	BMI	L82DA
	CMP	#10
	BMI	L82CD
	SEC
	SBC	#7
	CMP	#10
	BMI	L82DA
L82CD:
	CMP	0,X
	BPL	L82DA
	STA	2,X
	LDA	#1
	PHA
	TYA
	JMP	PUT
L82DA:
	TYA
	PHA
	JMP	L855C

; ----------------------------------------------------------------------------
; Dictionary: (FIND) [FORTH].
; Manual stack: ( a1 a2 --- pta b tf ) (ok)
; Manual: ( a1 a2 --- ff ) (bad) 103 Searches the dictionary starting at the
; name field address a2, matching to the text at address a1. Returns the
; parameter field address, length in bytes of name field, and boolean true for
; a good match. If no match is found, only a boolean false is left.
L82DF:
	.BYTE	$86,"(FIND",$A9
	.WORD	L82B1	; LFA: previous name field in this vocabulary chain
; Dictionary search: SETUP puts starting NFA in N and counted-string pointer
; in N+2. Mask $3F compares length and smudge state while ignoring immediate
; bit. Names end with bit 7 set; shifting the XOR ignores that bit for
; comparison. On success return PFA, the header flag/length byte, and 1;
; otherwise follow the LFA until zero.
PFIND:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 2
	LDA	#2
	JSR	SETUP
	STX	XSAVE
; Try the next dictionary header (N points at its NFA).
L82F1:
	LDY	#0
	LDA	(N),Y
	EOR	(N+2),Y
	AND	#$3F
	BNE	L8328
L82FB:
	INY
	LDA	(N),Y
	EOR	(N+2),Y
	ASL	A
	BNE	L8326
	BCC	L82FB
	LDX	XSAVE
	DEX
	DEX
	DEX
	DEX
	CLC
	TYA
	ADC	#5
	ADC	N
	STA	2,X
	LDY	#0
	TYA
	ADC	N+1
	STA	3,X
	STY	1,X
	LDA	(N),Y
	STA	0,X
	LDA	#1
	PHA
	JMP	PUSH

L8326:
	BCS	L832D
; Skip remaining name bytes until the high-bit end marker.
L8328:
	INY
	LDA	(N),Y
	BPL	L8328
; Read the two-byte link following the name; zero ends the chain.
L832D:
	INY
	LDA	(N),Y
	TAX
	INY
	LDA	(N),Y
	STA	N+1
	STX	N
	ORA	N
	BNE	L82F1
	LDX	XSAVE
	LDA	#0
	PHA
	JMP	PUSH

; ----------------------------------------------------------------------------
; Dictionary: ENCLOSE [FORTH].
; Manual stack: ( a c --- ) ( a1 n1 n2 n3 )
; Manual: The text scanning primitive used by WORD. From the text address a1
; and an ASCII delimiting character c is determined the byte offset to the
; first non-delimiter character n1, the offset to the first character
; delimiter after the text n2, and the offset to the first character not
; included. This procedure will not proceed past an ASCII 'null", treating it
; as an unconditional delimiter.
L8344:	.BYTE	$87,"ENCLOS",$C5
	.WORD	L82DF	; LFA: previous name field in this vocabulary chain
; Scan from a1 past leading delimiter bytes, then through the token until a
; delimiter or NUL. Return the original address and three offsets (start,
; end, next). Y and the pointer high byte cooperate to scan beyond one page.
ENCL:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 2
	LDA	#2
	JSR	SETUP
	TXA
	SEC
	SBC	#8
	TAX
	STY	3,X
	STY	1,X
	DEY
	DEC	N+3
	DEC	1,X
L8363:
	INY
	BNE	L836A
	INC	N+3
	INC	1,X
L836A:
	LDA	(N+2),Y
	CMP	N
	BEQ	L8363
	STY	4,X
	LDA	1,X
	STA	5,X
L8376:
	LDA	(N+2),Y
	BNE	L8396
	STY	2,X
	STY	0,X
	LDA	1,X
	STA	3,X
	TYA
	CMP	4,X
	BNE	L8393
	LDA	1,X
	CMP	5,X
	BNE	L8393
	INC	2,X
	BNE	L8393
	INC	3,X
L8393:
	JMP	NEXT

L8396:
	PHA
	STY	2,X
	LDA	1,X
	STA	3,X
	INY
	BNE	L83A4
	INC	1,X
	INC	N+3
L83A4:
	PLA
	CMP	N
	BNE	L8376
	STY	0,X
	JMP	NEXT


; ----------------------------------------------------------------------------
; Dictionary: EMIT [FORTH].
; Manual stack: ( c1 --- )
; Manual: Sends the character c1 to the selected output device. OUT is
; incremented for each character output. The output device is determined by
; the most recent use of the SYSTEM call CHKOUT. Normally characters are sent
; to the video screen. This is a vectored word.
L83AE:
	.BYTE	$84,"EMI",$D4
	.WORD	L8344	; LFA: previous name field in this vocabulary chain
EMIT:
	.WORD	DOVEC	; CFA: vectored word; dispatch through UP+$32+offset
	.BYTE	2	; Vector byte offset 2 from I/O (UP+$32)

PEMIT:
	.WORD	DOCOL
	.WORD	L964F
	.WORD	ONE
	.WORD	OUT
	.WORD	PSTOR
	.WORD	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: KEY [FORTH].
; Manual stack: ( --- n1 )
; Manual: Returns value n1, the ASCII key value of the key pressed on the
; keyboard. Before returning with the key value, the 132 key pressed is
; checked to see if it is in the key capture table. If it is, the associated
; function is executed, and another key is obtained from the keyboard. This
; is a vectored word.
L83C4:
	.BYTE	$83,"KE",$D9
	.WORD	L83AE	; LFA: previous name field in this vocabulary chain
KEY:
	.WORD	DOVEC	; CFA: vectored word; dispatch through UP+$32+offset
	.BYTE	0	; Vector byte offset 0 from I/O (UP+$32)

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
L842F:
	.BYTE	$89,"?TERMINA",$CC
	.WORD	L83C4	; LFA: previous name field in this vocabulary chain
QTER:
	.WORD	DOVEC	; CFA: vectored word; dispatch through UP+$32+offset
	.BYTE	4	; Vector byte offset 4 from I/O (UP+$32)

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
L844E:
	.BYTE	$82,"C",$D2
	.WORD	L842F	; LFA: previous name field in this vocabulary chain
CR:
	.WORD	DOVEC	; CFA: vectored word; dispatch through UP+$32+offset
	.BYTE	6	; Vector byte offset 6 from I/O (UP+$32)

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
L8464:
	.BYTE	$86,"VRESE",$D4
	.WORD	L844E	; LFA: previous name field in this vocabulary chain
VRESET:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	VWORDS
	.WORD	IO
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	28
	.WORD	CMOVE
	.WORD	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: CMOVE [FORTH].
; Manual stack: ( from to count --- )
; Manual: Moves the specified quantity of bytes beginning at address from to
; address to. The contents of address from is moved first proceeding toward
; high memory. Further specification is necessary on word processing
; computers.
L847A:	
    .BYTE	$85,"CMOV",$C5
	.WORD	L8464	; LFA: previous name field in this vocabulary chain
; Forward byte copy ( src dst count -- ). SETUP lays out count at N,
; destination at N+2, source at N+4. Y traverses each page and pointer high
; bytes advance on wrap. Overlap is safe only when forward copying will not
; overwrite unread source bytes.
CMOVE:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 3
	LDA	#3
	JSR	SETUP
; Test remaining count against Y, decrementing the high count on each match.
L8489:
	CPY	N
	BNE	L8494
	DEC	N+1
	BPL	L8494
	JMP	NEXT

; Copy one byte; wrap Y and increment both pointer high bytes at page end.
L8494:
	LDA	(N+4),Y
	STA	(N+2),Y
	INY
	BNE	L8489
	INC	N+5
	INC	N+3
	JMP	L8489

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
L84A2:
	.BYTE	$85,"SMOV",$C5
	.WORD	L847A	; LFA: previous name field in this vocabulary chain
; Display helper: copy exactly 40 bytes backwards, subtracting 64 from
; character values >=64 to form screen codes. Restoring XSAVE means the two
; address arguments remain on the data stack.
SMOVE:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: U* [FORTH].
; Manual stack: ( u1 u2 --- ud )
; Manual: Leaves the unsigned double number product of two unsigned numbers.
L84C7:
	.BYTE	$82,"U",$AA
	.WORD	L84A2	; LFA: previous name field in this vocabulary chain
; Unsigned 16x16 multiply producing a 32-bit result in the two input cells.
; Sixteen shift/add iterations; N holds a saved multiplicand. The high result
; cell is at the top of stack.
USTAR:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 2
	LDA	2,X
	STA	N
	STY	2,X
	LDA	3,X
	STA	N+1
	STY	3,X
	LDY	#16
; One multiplication bit: shift partial product, add saved multiplicand if
; needed.
L84DC:
	ASL	2,X
	ROL	3,X
	ROL	0,X
	ROL	1,X
	BCC	L84FB
	CLC
	LDA	N
	ADC	2,X
	STA	2,X
	LDA	N+1
	ADC	3,X
	STA	3,X
	BCC	L84FB
	INC	0,X
	BNE	L84FB
	INC	1,X
L84FB:
	DEY
	BNE	L84DC
	JMP	NEXT

; ----------------------------------------------------------------------------
; Dictionary: U/ [FORTH].
; Manual stack: ( ud u1 --- u2 u3)
; Manual: Leaves the unsigned remainder of u2 and unsigned quotient u3 from
; the unsigned double dividend ud and unsigned divisor u1.
L8501:
	.BYTE	$82,"U",$AF
	.WORD	L84C7	; LFA: previous name field in this vocabulary chain
; Unsigned restoring division: divide a 32-bit dividend by a 16-bit divisor
; over sixteen iterations. Leaves remainder below quotient. There is no
; explicit divide-by-zero or quotient-overflow check here.
USLAS:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 3
    lda 0,x
    ora 1,x
    bne :+
    lda #31
    jmp shell_error
:   STY N+1
	LDA	4,X
	LDY	2,X
	STY	4,X
	ASL	A
	STA	2,X
	LDA	5,X
	LDY	3,X
	STY	5,X
	ROL	A
	STA	3,X
	LDA	#16
	STA	N
; One division bit: shift remainder, trial-subtract divisor, retain
; successful subtraction.
L8520:
	ROL	4,X
	ROL	5,X
	ROL	N+1
	SEC
	LDA	4,X
	SBC	0,X
	TAY
	LDA	5,X
	SBC	1,X
	PHA
	LDA	N+1
	SBC	#0
	LDA	#0
	STA	N+1
	PLA
	BCC	L8540
	STY	4,X
	STA	5,X
; Shift success/failure carry into quotient; repeat for sixteen bits.
L8540:
	ROL	2,X
	ROL	3,X
	DEC	N
	BNE	L8520
	JMP	POP

; ----------------------------------------------------------------------------
; Dictionary: AND [FORTH].
; Stack (from code): ( x1 x2 -- x3 )
; Manual: Leaves the bitwise logical AND of n1 and n2 as n3.
L854B:
	.BYTE	$83,"AN",$C4
	.WORD	L8501	; LFA: previous name field in this vocabulary chain
ANDD:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 2
	LDA	0,X
	AND	2,X
	PHA
	LDA	1,X
	AND	3,X
L855C:
	INX
	INX
	JMP	PUT

; ----------------------------------------------------------------------------
; Dictionary: OR [FORTH].
; Stack (from code): ( x1 x2 -- x3 )
; Manual: Leaves the bit-wise logical or of two 16-bit values.
L8561:
	.BYTE	$82,"O",$D2
	.WORD	L854B	; LFA: previous name field in this vocabulary chain
ORR:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 2
	LDA	0,X
	ORA	2,X
	PHA
	LDA	1,X
	ORA	3,X
	JMP	L855C

; ----------------------------------------------------------------------------
; Dictionary: XOR [FORTH].
; Stack (from code): ( x1 x2 -- x3 )
; Manual: Leaves the bitwise logical exclusive-or of the two values.
L8574:
	.BYTE	$83,"XO",$D2
	.WORD	L8561	; LFA: previous name field in this vocabulary chain
XORR:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 2
	LDA	0,X
	EOR	2,X
	PHA
	LDA	1,X
	EOR	3,X
	JMP	L855C

; ----------------------------------------------------------------------------
; Dictionary: SP@ [FORTH].
; Manual stack: ( --- a )
; Manual: Returns the address of the stack position to the top of the stack,
; as it was before SP@ was executed. (e.g. 1 2 SP@ @ ... would type 2 2 1 ).
L8588:
	.BYTE	$83,"SP",$C0
	.WORD	L8574	; LFA: previous name field in this vocabulary chain
SPAT:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
	TXA

PUSH0A:
	PHA
	LDA	#0
	JMP	PUSH

; ----------------------------------------------------------------------------
; Dictionary: SP! [FORTH].
; Stack (from code): ( ... -- ) Reset data stack to S0.
; Manual: Clears the stack.
L8597:
	.BYTE	$83,"SP",$A1
	.WORD	L8588	; LFA: previous name field in this vocabulary chain
; Reset X from the initial stack pointer at UP+6. This SP! does not consume a
; caller-supplied pointer; it resets the data stack.
SPSTO:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
	LDY	#6
	LDA	(UP),Y
	TAX
	JMP	NEXT

; ----------------------------------------------------------------------------
; Dictionary: RP! [FORTH].
; Stack (from code): ( -- ) Reset return stack to R0.
; Manual: A computer dependent procedure to initialize the return stack
; pointer.
L85A7:
	.BYTE	$83,"RP",$A1
	.WORD	L8597	; LFA: previous name field in this vocabulary chain
; Reset the hardware stack pointer from UP+8 while preserving data-stack X.
; Any outstanding return addresses / loop frames are discarded.
RPSTO:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
	STX	XSAVE
	LDY	#8
	LDA	(UP),Y
	TAX
	TXS
	LDX	XSAVE
	JMP	NEXT

; ----------------------------------------------------------------------------
; Dictionary: ;S [FORTH].
; Manual: Stops interpretation of a screen. ;S is also the run-time word
; compiled at the end of a colon-definition which returns execution to the
; calling procedure.
L85BC:
	.BYTE	$82,";",$D3
	.WORD	L85A7	; LFA: previous name field in this vocabulary chain
; Return from a colon definition: restore IP low/high from the hardware
; return stack and enter NEXT. This is the Forth return operation, not a 6502
; RTS.
SEMIS:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
	PLA
	STA	IP
	PLA
	STA	IP+1
	JMP	NEXT

; ----------------------------------------------------------------------------
; Dictionary: LEAVE [FORTH].
; Manual: Forces termination of a DO-LOOP at the next opportunity by setting
; the loop limit equal to the current value of the index. The index itself
; remains unchanged, and execution proceeds normally until LOOP or +LOOP is
; encountered.
L85CC:
	.BYTE	$85,"LEAV",$C5
	.WORD	L85BC	; LFA: previous name field in this vocabulary chain
; Copy current loop index into its limit. Execution continues through the
; loop body until its next (LOOP)/(+LOOP) test; this is the older fig-Forth
; LEAVE behavior.
LEAVE:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
	STX	XSAVE
	TSX
	LDA	$101,X
	STA	$103,X
	LDA	$102,X
	STA	$104,X
	LDX	XSAVE
	JMP	NEXT

; ----------------------------------------------------------------------------
; Dictionary: >R [FORTH].
; Manual stack: ( n --- )
; Manual: Removes a number from the computation stack and places as the most
; accessible on the return stack. Use should be balanced with R> in the same
; definition.
L85EA:
	.BYTE	$82,">",$D2
	.WORD	L85CC	; LFA: previous name field in this vocabulary chain
; Move a cell to the hardware return stack, high byte first. This stack also
; holds colon return IPs, loop frames and temporary native JSR/PHA data.
TOR:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 1
	LDA	1,X
	PHA
	LDA	0,X
	PHA
	JMP	POP

; ----------------------------------------------------------------------------
; Dictionary: R> [FORTH].
; Manual stack: ( --- n )
; Manual: Removes the top value from the return stack and leaves it on the
; computation stack. See >R and R.
L85FA:
	.BYTE	$82,"R",$BE
	.WORD	L85EA	; LFA: previous name field in this vocabulary chain
RFROM:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
	DEX
	DEX
	PLA
	STA	0,X
	PLA
	STA	1,X
	JMP	NEXT

; ----------------------------------------------------------------------------
; Dictionary: R [FORTH].
; Manual stack: ( --- n )
; Manual: Copies the top of the return stack to the computation stack.
L860C:
	.BYTE	$81,$D2
	.WORD	L85FA	; LFA: previous name field in this vocabulary chain
; Fetch the top return-stack cell without removing it. I uses the same native
; entry (R+2) while a loop index is on top.
R:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
	STX	XSAVE
	TSX
	LDA	$101,X
	PHA
	LDA	$102,X
	LDX	XSAVE
	JMP	PUSH

; ----------------------------------------------------------------------------
; Dictionary: 0= [FORTH].
; Stack (from code): ( x -- flag )
; Manual: Leaves a true flag if the number is equal to zero; otherwise leaves
; a false flag.
L8621:
	.BYTE	$82,"0",$BD
	.WORD	L860C	; LFA: previous name field in this vocabulary chain
ZEQU:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 1
	LDA	0,X
	ORA	1,X
	STY	1,X
	BNE	L8631
	INY
L8631:
	STY	0,X
	JMP	NEXT

; ----------------------------------------------------------------------------
; Dictionary: 0< [FORTH].
; Stack (from code): ( n -- flag )
; Manual: Leaves a true flag if the number is less than zero (negative);
; otherwise leaves a false flag.
L8636:
	.BYTE	$82,"0",$BC
	.WORD	L8621	; LFA: previous name field in this vocabulary chain
ZLESS:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 1
	ASL	1,X
	TYA
	ROL	A
	STY	1,X
	STA	0,X
	JMP	NEXT

; ----------------------------------------------------------------------------
; Dictionary: + [FORTH].
; Manual stack: ( n1 n2 --- sum )
; Manual: Leaves the sum of n1 + n2 on the stack.
L8648:
	.BYTE	$81,$AB
	.WORD	L8636	; LFA: previous name field in this vocabulary chain
PLUS:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 2
	CLC
	LDA	0,X
	ADC	2,X
	STA	2,X
	LDA	1,X
	ADC	3,X
	STA	3,X
	JMP	POP

; ----------------------------------------------------------------------------
; Dictionary: D+ [FORTH].
; Stack (from code): ( d1 d2 -- d3 )
; Manual: Leaves the double number sum of two double numbers.
L865E:
	.BYTE	$82,"D",$AB
	.WORD	L8648	; LFA: previous name field in this vocabulary chain
; Add low cells first, then high cells with carry propagated across all four
; bytes. Doubles occupy low-cell then high-cell order, with the high cell
; nearest X.
DPLUS:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 4
	CLC
	LDA	2,X
	ADC	6,X
	STA	6,X
	LDA	3,X
	ADC	7,X
	STA	7,X
	LDA	0,X
	ADC	4,X
	STA	4,X
	LDA	1,X
	ADC	5,X
	STA	5,X
	JMP	POPTWO

; ----------------------------------------------------------------------------
; Dictionary: MINUS [FORTH].
; Stack (from code): ( n -- -n )
; Manual: Leaves the two's complement of a number.
L8681:
	.BYTE	$85,"MINU",$D3
	.WORD	L865E	; LFA: previous name field in this vocabulary chain
MINUS:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 1
	SEC
negate_cell:
	TYA
	SBC	0,X
	STA	0,X
	TYA
	SBC	1,X
	STA	1,X
	JMP	NEXT

; ----------------------------------------------------------------------------
; Dictionary: DMINUS [FORTH].
; Stack (from code): ( d -- -d )
; Manual: Converts d1 to its double number two's complement.
L8699:
	.BYTE	$86,"DMINU",$D3
	.WORD	L8681	; LFA: previous name field in this vocabulary chain
; Two-cell negation: subtract the low cell from zero, then enter negate_cell with
; its borrow still in carry. The shared tail negates the high cell without
; resetting carry.
DMINU:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 2
	SEC
	TYA
	SBC	2,X
	STA	2,X
	TYA
	SBC	3,X
	STA	3,X
	JMP	negate_cell

; ----------------------------------------------------------------------------
; Dictionary: OVER [FORTH].
; Manual stack: ( n1 n2 --- n1 n2 n1 )
; Manual: Copies the second stack value, placing it as the new top.
L86B2:
	.BYTE	$84,"OVE",$D2
	.WORD	L8699	; LFA: previous name field in this vocabulary chain
OVER:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 2
	LDA	2,X
	PHA
	LDA	3,X
	JMP	PUSH

; ----------------------------------------------------------------------------
; Dictionary: DROP [FORTH].
; Manual stack: ( n --- )
; Manual: Drops the number from the stack.
L86C3:
	.BYTE	$84,"DRO",$D0
	.WORD	L86B2	; LFA: previous name field in this vocabulary chain
DROP:
	.WORD	POP

; ----------------------------------------------------------------------------
; Dictionary: 2DROP [FORTH].
; Manual stack: ( n1/n2 --- ) or ( d1 --- )
; Manual: Drops the top two single length elements (16-bits) from the data
; stack, or one double length (32-bits) element from the stack. Pronounced
; "two drop."
L86CC:
	.BYTE	$85,"2DRO",$D0
	.WORD	L86C3	; LFA: previous name field in this vocabulary chain
TDROP:
	.WORD	POPTWO

; ----------------------------------------------------------------------------
; Dictionary: SWAP [FORTH].
; Manual stack: ( n1 n2 --- n2 n1 )
; Manual: Exchanges the top two values on the stack.
L86D6:
	.BYTE	$84,"SWA",$D0
	.WORD	L86CC	; LFA: previous name field in this vocabulary chain
SWAP:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 2
	LDA	2,X
	PHA
	LDA	0,X
	STA	2,X
	LDA	3,X
	LDY	1,X
	STY	3,X
	JMP	PUT

; ----------------------------------------------------------------------------
; Dictionary: DUP [FORTH].
; Manual stack: ( n --- n n )
; Manual: Duplicates the value on the stack.
L86EF:
	.BYTE	$83,"DU",$D0
	.WORD	L86D6	; LFA: previous name field in this vocabulary chain
DUP:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 1
	LDA	0,X
	PHA
	LDA	1,X
	JMP	PUSH

; ----------------------------------------------------------------------------
; Dictionary: +! [FORTH].
; Stack (from code): ( n addr -- )
; Manual: Adds n to the value at the address, a. Pronounced "plus-store."
L86FF:
	.BYTE	$82,"+",$A1
	.WORD	L86EF	; LFA: previous name field in this vocabulary chain
PSTOR:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 2
	CLC
	LDA	(0,X)
	ADC	2,X
	STA	(0,X)
	INC	0,X
	BNE	L8713
	INC	1,X
L8713:
	LDA	(0,X)
	ADC	3,X
	STA	(0,X)
	JMP	POPTWO

; ----------------------------------------------------------------------------
; Dictionary: TOGGLE [FORTH].
; Stack (from code): ( addr mask -- )
; Manual: Complement the contents of address a, by the bit pattern b.
L871C:
	.BYTE	$86,"TOGGL",$C5
	.WORD	L86FF	; LFA: previous name field in this vocabulary chain
TOGGL:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 2
	LDA	(2,X)
	EOR	0,X
	STA	(2,X)
	JMP	POPTWO

;	@

; ----------------------------------------------------------------------------
; Dictionary: @ [FORTH].
; Stack (from code): ( addr -- x )
; Manual: Leaves the 16-bit contents of the address, a. Pronounced "fetch."
L8730:
	.BYTE	$81,$C0
	.WORD	L871C	; LFA: previous name field in this vocabulary chain
AT:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 1
	LDA	(0,X)
	PHA
	INC	0,X
	BNE	L873F
	INC	1,X
L873F:
	LDA	(0,X)
	JMP	PUT

; ----------------------------------------------------------------------------
; Dictionary: C@ [FORTH].
; Stack (from code): ( addr -- byte )
; Manual: Leaves the 8-bit contents of memory address. On word addressing
; computers, further specification is needed regarding byte addressing.
L8744:
	.BYTE	$82,"C",$C0
	.WORD	L8730	; LFA: previous name field in this vocabulary chain
CAT:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 1
	LDA	(0,X)
	STA	0,X
	STY	1,X
	JMP	NEXT

; ----------------------------------------------------------------------------
; Dictionary: ! [FORTH].
; Stack (from code): ( x addr -- )
; Manual: Stores the value of n (16 bits) at address a1. Pronounced "store"
L8754:
	.BYTE	$81,$A1
	.WORD	L8744	; LFA: previous name field in this vocabulary chain
STORE:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 2
	LDA	2,X
	STA	(0,X)
	INC	0,X
	BNE	L8764
	INC	1,X
L8764:
	LDA	3,X
	STA	(0,X)
	JMP	POPTWO

; ----------------------------------------------------------------------------
; Dictionary: C! [FORTH].
; Stack (from code): ( byte addr -- )
; Manual: Stores 8 bits at address specified. On word addressing computers,
; further specification is necessary regarding byte addressing.
L876B:
	.BYTE	$82,"C",$A1
	.WORD	L8754	; LFA: previous name field in this vocabulary chain
CSTOR:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 2
	LDA	2,X
	STA	(0,X)
	JMP	POPTWO

; ============================================================================
; DEFINING WORDS, CONSTANTS AND USER VARIABLES
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
L8779:
	.BYTE	$C1,$BA
	.WORD	L876B	; LFA: previous name field in this vocabulary chain
COLON:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	QEXEC
    .word BEGIN_DEFINITION
	.WORD	SCSP
	.WORD	CURR
	.WORD	AT
	.WORD	CONT
	.WORD	STORE
	.WORD	CREAT
	.WORD	RBRAC
	.WORD	PSCOD
; Colon runtime: save the caller IP high/low on the return stack, set IP=W+2
; (the parameter field), and execute NEXT. A colon definition is a stream of
; CFA cells, not native JSR instructions.
DOCOL:
	LDA	IP+1
	PHA
	LDA	IP
	PHA
	CLC
	LDA	W
	ADC	#2
	STA	IP
	TYA
	ADC	W+1
	STA	IP+1
	JMP	NEXT

; ---------------------------------------------------------------------------
; Dictionary: ; [FORTH]; immediate (executes during compilation).
; Manual: Terminates a colon-definition and stops further compilation.
; Compiles the run-time ;S. The ; must be preceeded by a space in a
; colon-definition.
L87A6:
	.BYTE	$C1,$BB
	.WORD	L8779	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	QCSP
	.WORD	COMP
	.WORD	SEMIS	; Inline CFA operand consumed by COMPILE
	.WORD	SMUDGE
	.WORD	LBRAC
    .word END_DEFINITION
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: CONSTANT [FORTH].
; Manual stack: ( n --- )
; Manual: A defining word used in the form: n CONSTANT cccc to create word
; cccc, with its parameter field containing n. When cccc is later executed,
; it will push the value of n to the stack.
L87B8:
	.BYTE	$88,"CONSTAN",$D4
	.WORD	L87A6	; LFA: previous name field in this vocabulary chain
CONST:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	CREAT
	.WORD	SMUDGE
	.WORD	COMMA
	.WORD	PSCOD
; Constant runtime: fetch the little-endian parameter cell at W+2 and push
; its value.
DOCON:
	LDY	#2
	LDA	(W),Y
	PHA
	INY
	LDA	(W),Y
	JMP	PUSH

; ---------------------------------------------------------------------------
; Dictionary: VARIABLE [FORTH].
; Manual: A defining word used in the form: n VARIABLE cccc When VARIABLE is
; executed, it creates the definition cccc with its parameter field
; initialized to n. When cccc is later executed, the address of its parameter
; field (containing n) is left on the stack, so that a fetch (@) or store (!)
; may have access to this location.
L87D8:
	.BYTE	$88,"VARIABL",$C5
	.WORD	L87B8	; LFA: previous name field in this vocabulary chain
VAR:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	CONST
	.WORD	PSCOD
; Variable runtime: push W+2, the parameter-field address. For ROM-resident
; tables this address is readable data, not necessarily writable storage.
DOVAR:
	CLC
	LDA	W
	ADC	#2
	PHA
	TYA
	ADC	W+1
	JMP	PUSH

; ---------------------------------------------------------------------------
; Dictionary: USER [FORTH].
; Manual stack: ( n --- )
; Manual: A defining word used in the form: n USER cccc which creates a user
; variable cccc. The parameter field of cccc contains n as a fixed offset
; relative to the user pointer register UP for this user variable. When cccc
; is later executed, It places the sum of its offset and the user area base
; address on the stack as the storage address of that particular variable.
L87F5:
	.BYTE	$84,"USE",$D2
	.WORD	L87D8	; LFA: previous name field in this vocabulary chain
USER:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	CONST
	.WORD	PSCOD
; User runtime: read only the byte at W+2 and add it to UP. Some later
; definitions store the offset as .WORD, but its high byte is still ignored.
DOUSE:
	LDY	#2
	CLC
	LDA	(W),Y
	ADC	UP
	PHA
	LDA	#0
	ADC	UP+1
	JMP	PUSH

; ---------------------------------------------------------------------------
; Dictionary: 0 [FORTH].
; Implementation: ( -- 0 ) Push the constant zero.
L8811:
	.BYTE	$81,$B0
	.WORD	L87F5	; LFA: previous name field in this vocabulary chain
ZERO:
	.WORD	DOCON	; CFA: constant; push the following 16-bit value
	.WORD	0

; ---------------------------------------------------------------------------
; Dictionary: 1 [FORTH].
; Implementation: ( -- 1 ) Push the constant one.
L8819:
	.BYTE	$81,$B1
	.WORD	L8811	; LFA: previous name field in this vocabulary chain
ONE:
	.WORD	DOCON	; CFA: constant; push the following 16-bit value
	.WORD	1

; ---------------------------------------------------------------------------
; Dictionary: 2 [FORTH].
; Implementation: ( -- 2 ) Push the constant two.
L8821:
	.BYTE	$81,$B2
	.WORD	L8819	; LFA: previous name field in this vocabulary chain
TWO:
	.WORD	DOCON	; CFA: constant; push the following 16-bit value
	.WORD	2

; ---------------------------------------------------------------------------
; Dictionary: 3 [FORTH].
; Implementation: ( -- 3 ) Push the constant three.
L8829:
	.BYTE	$81,$B3
	.WORD	L8821	; LFA: previous name field in this vocabulary chain
THREE:
	.WORD	DOCON	; CFA: constant; push the following 16-bit value
	.WORD	3

; ---------------------------------------------------------------------------
; Dictionary: BL [FORTH].
; Manual stack: ( --- c )
; Manual: A constant that leaves the ASCII value for "blank." 113
L8831:
	.BYTE	$82,"B",$CC
	.WORD	L8829	; LFA: previous name field in this vocabulary chain
BL:
	.WORD	DOCON	; CFA: constant; push the following 16-bit value
	.WORD	32

; ---------------------------------------------------------------------------
; Dictionary: C/L [FORTH].
; Manual: Characters per line.
L883A:
	.BYTE	$83,"C/",$CC
	.WORD	L8831	; LFA: previous name field in this vocabulary chain
CSLL:
	.WORD	DOCON	; CFA: constant; push the following 16-bit value
	.WORD	64

; ---------------------------------------------------------------------------
; Dictionary: FIRST [FORTH].
; Manual stack: ( --- n )
; Manual: A constant that leaves the address of the first (lowest) block
; buffer.
L8844:
	.BYTE	$85,"FIRS",$D4
	.WORD	L883A	; LFA: previous name field in this vocabulary chain
FIRST:
	.WORD	DOCON	; CFA: constant; push the following 16-bit value
	.WORD	BUFONE

; ---------------------------------------------------------------------------
; Dictionary: LIMIT [FORTH].
; Manual stack: ( --- n )
; Manual: A constant leaving the address just above the highest memory
; available for a disk or cassette buffer. Usually this is the highest memory
; system.
L8850:
	.BYTE	$85,"LIMI",$D4
	.WORD	L8844	; LFA: previous name field in this vocabulary chain
LIMIT:
	.WORD	DOCON	; CFA: constant; push the following 16-bit value
	.WORD	$8000

; ---------------------------------------------------------------------------
; Dictionary: B/BUF [FORTH].
; Manual stack: ( --- n1 )
; Manual: A constant which returns the number of bytes per FORTH buffer. A
; value of 1024 in this system.
L885C:
	.BYTE	$85,"B/BU",$C6
	.WORD	L8850	; LFA: previous name field in this vocabulary chain
BBUF:
	.WORD	DOCON	; CFA: constant; push the following 16-bit value
	.WORD	1024

; ---------------------------------------------------------------------------
; Dictionary: B/SCR [FORTH].
; Manual stack: ( --- n1 )
; Manual: A constant which returns the number of blocks per FORTH buffer. A
; value of 1 (one) in this system.
L8868:
	.BYTE	$85,"B/SC",$D2
	.WORD	L885C	; LFA: previous name field in this vocabulary chain
BSCR:
	.WORD	DOCON	; CFA: constant; push the following 16-bit value
	.WORD	1

; ---------------------------------------------------------------------------
; Dictionary: +ORIGIN [FORTH].
; Manual stack: ( n --- a )
; Manual: Leaves the memory address relative to n to the origin parameter
; area. N is the minimum address unit, either byte or word. This definition
; is used to have access to or modify the boot-up parameters at the origin
; area.
L8874:
	.BYTE	$87,"+ORIGI",$CE
	.WORD	L8868	; LFA: previous name field in this vocabulary chain
PORIG:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	LIT,ORIG
	.WORD	PLUS
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: TIB [FORTH].
; Manual stack: ( --- a )
; Manual: A user variable containing the addresses of the terminal input
; buffer.
L8888:
	.BYTE	$83,"TI",$C2
	.WORD	L8874	; LFA: previous name field in this vocabulary chain
TIB:
	.WORD	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.BYTE	$A	; User offset $000A; initial address $094A

; ---------------------------------------------------------------------------
; Dictionary: WIDTH [FORTH].
; Manual stack: ( --- a )
; Manual: In fig-FORTH, a user variable containing the maximum number of
; letters saved in the compilation of a definitions' name. It must be 1
; through 31, with a default value of 31. The name character count and its
; natural characters are saved, up to the value in WIDTH. The value may be
; changed at any time within the above limits.
L8891:
	.BYTE	$85,"WIDT",$C8
	.WORD	L8888	; LFA: previous name field in this vocabulary chain
WIDTH:
	.WORD	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.BYTE	$C	; User offset $000C; initial address $094C

; ---------------------------------------------------------------------------
; Dictionary: FENCE [FORTH].
; Manual stack: ( --- a )
; Manual: A user variable containing an address below which FORGETting is
; trapped. To FORGET below this point, the user must alter the contents of
; FENCE.
L889C:
	.BYTE	$85,"FENC",$C5
	.WORD	L8891	; LFA: previous name field in this vocabulary chain
FENCE:
	.WORD	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.BYTE	$10	; User offset $0010; initial address $0950

; ---------------------------------------------------------------------------
; Dictionary: DP [FORTH].
; Manual stack: ( --- a )
; Manual: A user variable, the dictionary pointer, which contains the address
; of the next free memory above the dictionary. The value may be read by HERE
; and altered by ALLOT.
L88A7:
	.BYTE	$82,"D",$D0
	.WORD	L889C	; LFA: previous name field in this vocabulary chain
DP:	.WORD	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.BYTE	$12	; User offset $0012; initial address $0952

; ---------------------------------------------------------------------------
; Dictionary: VOC-LINK [FORTH].
; Manual stack: ( --- a )
; Manual: A user variable containing the address of a field in the definition
; of most recently created vocabulary. All vocabulary names are linked by
; these fields to allow control for FORGETting through multiple vocabularies.
L88AF:
	.BYTE	$88,"VOC-LIN",$CB
	.WORD	L88A7	; LFA: previous name field in this vocabulary chain
VOCL:
	.WORD	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.BYTE	$14	; User offset $0014; initial address $0954

; ---------------------------------------------------------------------------
; Dictionary: BLK [FORTH].
; Manual stack: ( --- a )
; Manual: A user variable containing the block number being interpreted. If
; zero, input is being taken from the terminal input buffer.
L88BD:
	.BYTE	$83,"BL",$CB
	.WORD	L88AF	; LFA: previous name field in this vocabulary chain
BLK:
	.WORD	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.BYTE	$16	; User offset $0016; initial address $0956

; ---------------------------------------------------------------------------
; Dictionary: IN [FORTH].
; Manual stack: ( --- a )
; Manual: A user variable containing the byte offset within the current input
; text buffer (terminal or disk) from which the next text will be accepted.
; WORD uses and moves the value of IN.
L88C6:
	.BYTE	$82,"I",$CE
	.WORD	L88BD	; LFA: previous name field in this vocabulary chain
IN:
	.WORD	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.BYTE	$18	; User offset $0018; initial address $0958

; ---------------------------------------------------------------------------
; Dictionary: OUT [FORTH].
; Manual stack: ( --- a )
; Manual: A user variable that contains a value incremented by EMIT. The user
; may alter and examine OUT to control display formatting.
L88CE:
	.BYTE	$83,"OU",$D4
	.WORD	L88C6	; LFA: previous name field in this vocabulary chain
OUT:
	.WORD	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.BYTE	$1A	; User offset $001A; initial address $095A

; ---------------------------------------------------------------------------
; Dictionary: SCR [FORTH].
; Manual stack: ( --- a )
; Manual: A user variable containing the screen number most recently
; referenced by LIST.
L88D7:
	.BYTE	$83,"SC",$D2
	.WORD	L88CE	; LFA: previous name field in this vocabulary chain
SCR:
	.WORD	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.BYTE	$1C	; User offset $001C; initial address $095C

; ---------------------------------------------------------------------------
; Dictionary: BMAX [FORTH].
; Manual stack: ( --- a1 )
; Manual: The FORTH user variable which specifies the highest screen that
; will be accessible with BLOCK operations. This variable is initialized to
; 16, equal to the number of screen buffers available.
L88E0:
	.BYTE	$84,"BMA",$D8
	.WORD	L88D7	; LFA: previous name field in this vocabulary chain
BMAX:
	.WORD	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.BYTE	$1E	; User offset $001E; initial address $095E

; ---------------------------------------------------------------------------
; Dictionary: CONTEXT [FORTH].
; Manual stack: ( --- a )
; Manual: A user variable containing a pointer to the vocabulary within which
; dictionary searches will first begin.
L88EA:
	.BYTE	$87,"CONTEX",$D4
	.WORD	L88E0	; LFA: previous name field in this vocabulary chain
CONT:	.WORD	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.BYTE	$20	; User offset $0020; initial address $0960

; ---------------------------------------------------------------------------
; Dictionary: CURRENT [FORTH].
; Manual stack: ( --- a1 )
; Manual: Leaves the address of the variable that specifies the vocabulary
; into which you are adding new word definitions.
L88F7:
	.BYTE	$87,"CURREN",$D4
	.WORD	L88EA	; LFA: previous name field in this vocabulary chain
CURR:
	.WORD	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.BYTE	$22	; User offset $0022; initial address $0962

; ---------------------------------------------------------------------------
; Dictionary: STATE [FORTH].
; Manual stack: ( --- a )
; Manual: A user variable containing the compilation state. A nonzero value
; indicates compilation. The value itself may be implementation dependent.
; 145
L8904:
	.BYTE	$85,"STAT",$C5
	.WORD	L88F7	; LFA: previous name field in this vocabulary chain
STATE:
	.WORD	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.BYTE	$24	; User offset $0024; initial address $0964

; ---------------------------------------------------------------------------
; Dictionary: BASE [FORTH].
; Manual stack: ( --- a )
; Manual: A user variable containing the current number base used for input
; and output conversion.
L890F:
	.BYTE	$84,"BAS",$C5
	.WORD	L8904	; LFA: previous name field in this vocabulary chain
BASE:
	.WORD	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.BYTE	$26	; User offset $0026; initial address $0966

; ---------------------------------------------------------------------------
; Dictionary: DPL [FORTH].
; Manual stack: ( --- a )
; Manual: A user variable containing the number of digits to the right of the
; decimal on double integer input. It may also be used to hold output column
; location of a decimal point, in user generated formatting. The default
; value on single number input is -1.
L8919:
	.BYTE	$83,"DP",$CC
	.WORD	L890F	; LFA: previous name field in this vocabulary chain
DPL:
	.WORD	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.BYTE	$28	; User offset $0028; initial address $0968

; ---------------------------------------------------------------------------
; Dictionary: CSP [FORTH].
; Manual stack: ( --- a )
; Manual: A user variable temporarily storing the stack pointer position for
; compilation error checking.
L8922:
	.BYTE	$83,"CS",$D0
	.WORD	L8919	; LFA: previous name field in this vocabulary chain
CSP:
	.WORD	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.BYTE	$2C	; User offset $002C; initial address $096C

; ---------------------------------------------------------------------------
; Dictionary: R# [FORTH].
; Manual stack: ( --- a )
; Manual: A user variable which may contain the location of an editing
; cursor, or other file related functions.
L892B:
	.BYTE	$82,"R",$A3
	.WORD	L8922	; LFA: previous name field in this vocabulary chain
RNUM:
	.WORD	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.BYTE	$2E	; User offset $002E; initial address $096E

; ---------------------------------------------------------------------------
; Dictionary: HLD [FORTH].
; Manual stack: ( --- a )
; Manual: A user variable that holds the address of the latest character of
; text during numeric output conversion. 130
L8933:
	.BYTE	$83,"HL",$C4
	.WORD	L892B	; LFA: previous name field in this vocabulary chain
HLD:
	.WORD	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.BYTE	$30	; User offset $0030; initial address $0970

; ---------------------------------------------------------------------------
; Dictionary: I/O [FORTH].
; Manual stack: ( --- a1 )
; Manual: A user array, containing the CFA's of the VECTORED words in
; 64FORTH. See the section on VECTORED WORDS, for further information.
L893C:
	.BYTE	$83,"I/",$CF
	.WORD	L8933	; LFA: previous name field in this vocabulary chain
IO:
	.WORD	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.BYTE	$32	; User offset $0032; initial address $0972

; ---------------------------------------------------------------------------
; Dictionary: F# [FORTH].
; Manual stack: ( --- a1 )
; Manual: A user variable, which holds the current file number for all READ
; and WRITE operations. Defaults to one (1) for CASSETTE operation.
L8945:
	.BYTE	$82,"F",$A3
	.WORD	L893C	; LFA: previous name field in this vocabulary chain
FNUM:
	.WORD	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.BYTE	$4C	; User offset $004C; initial address $098C

; ---------------------------------------------------------------------------
; Dictionary: D# [FORTH].
; Manual stack: ( --- a1 )
; Manual: A user variable, which holds the device number used for the READ
; and WRITE operators. Defaults to one (1), CASSETTE.
L894D:
	.BYTE	$82,"D",$A3
	.WORD	L8945	; LFA: previous name field in this vocabulary chain
DNUM:
	.WORD	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.BYTE	$4E	; User offset $004E; initial address $098E

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
L8955:
	.BYTE	$84,"CTB",$CC
	.WORD	L894D	; LFA: previous name field in this vocabulary chain
CTBL:
	.WORD	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.BYTE	$4A	; User offset $004A; initial address $098A

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
L895F:
	.BYTE	$85,"EFLA",$C7
	.WORD	L8955	; LFA: previous name field in this vocabulary chain
EFLAG:
	.WORD	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.BYTE	$C0	; User offset $00C0; initial address $0A00

; ---------------------------------------------------------------------------
; Dictionary: DR# [FORTH].
; Manual stack: ( --- a1 )
; Manual: A user variable which holds the device number of the currently
; active disk drive. Defaults to drive 0, device 8, and may be changed with
; the word DRIVE, and checked with the word DRIVE?.
L896A:
	.BYTE	$83,"DR",$A3
	.WORD	L895F	; LFA: previous name field in this vocabulary chain
DRNUM:
	.WORD	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.BYTE	$C2	; User offset $00C2; initial address $0A02

; ---------------------------------------------------------------------------
; Dictionary: DCHAN [FORTH].
; Implementation: ( -- addr ) Address of the disk data-channel user variable;
; cold start selects channel 7.
L8973:
	.BYTE	$85,"DCHA",$CE
	.WORD	L896A	; LFA: previous name field in this vocabulary chain
DCHAN:
	.WORD	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.BYTE	$C4	; User offset $00C4; initial address $0A04

; ---------------------------------------------------------------------------
; Dictionary: CURVOICE [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- a1 )
; Manual: A user variable, which holds the number of the current voice on
; which the sound control words are working. This is used to simplify and
; reduce the stack operations that have to be done when working with the
; complex sound system in the SID chip.
L897E:
	.BYTE	$88,"CURVOIC",$C5
	.WORD	L8973	; LFA: previous name field in this vocabulary chain
CURVOC:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: IFLAG [FORTH].
; Implementation: ( -- addr ) Address of the editor insert/overwrite flag.
L898C:
	.BYTE	$85,"IFLA",$C7
	.WORD	L897E	; LFA: previous name field in this vocabulary chain
IFLAG:
	.WORD	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.BYTE	$D4	; User offset $00D4; initial address $0A14

; ---------------------------------------------------------------------------
; Dictionary: FN [FORTH].
; Manual stack: ( --- a1 )
; Manual: A user array, which holds the name of the current file. This array
; is 65 characters long.
L8997:
	.BYTE	$82,"F",$CE
	.WORD	L898C	; LFA: previous name field in this vocabulary chain
FN:
	.WORD	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.BYTE	$7E	; User offset $007E; initial address $09BE

; ============================================================================
; HIGH-LEVEL COMPILER, PARSER AND OUTER INTERPRETER
; ============================================================================

; ---------------------------------------------------------------------------
; Dictionary: 1+ [FORTH].
; Manual stack: ( n1 --- n2 )
; Manual: Increments n1 by 1.
L899F:
	.BYTE	$82,"1",$AB
	.WORD	L8997	; LFA: previous name field in this vocabulary chain
ONEP:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	ONE
	.WORD	PLUS
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: 2+ [FORTH].
; Manual stack: ( n1 --- n2 )
; Manual: Leaves n1 incremented by 2.
L89AC:
	.BYTE	$82,"2",$AB
	.WORD	L899F	; LFA: previous name field in this vocabulary chain
TWOP:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	TWO
	.WORD	PLUS
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: HERE [FORTH].
; Manual stack: ( --- a )
; Manual: Leaves the address of the next available dictionary location.
L89B9:
	.BYTE	$84,"HER",$C5
	.WORD	L89AC	; LFA: previous name field in this vocabulary chain
HERE:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	DP
	.WORD	AT
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ALLOT [FORTH].
; Manual stack: ( n --- )
; Manual: Adds the signed number to the dictionary pointer DP. May be used to
; reserve dictionary space or re-origin memory. N is with regard to computer
; address type (byte or word).
L89C8:
	.BYTE	$85,"ALLO",$D4
	.WORD	L89B9	; LFA: previous name field in this vocabulary chain
ALLOT:
    .word allot_checked

; ---------------------------------------------------------------------------
; Dictionary: , [FORTH].
; Manual stack: ( n --- )
; Manual: Stores n into the next available dictionary memory cell, advancing
; the dictionary pointer. Pronounced "comma."
L89D8:
	.BYTE	$81,$AC
	.WORD	L89C8	; LFA: previous name field in this vocabulary chain
COMMA:
	.WORD	DOVEC	; CFA: vectored word; dispatch through UP+$32+offset
	.BYTE	20	; Vector byte offset 20 from I/O (UP+$32)

PCOMMA:
    .word comma_checked

; ---------------------------------------------------------------------------
; Dictionary: C, [FORTH].
; Manual stack: ( b --- )
; Manual: Stores 8 bits of b into the next available dictionary byte,
; advancing the dictionary pointer. This is only available on byte addressing
; computers.
L89EB:
	.BYTE	$82,"C",$AC
	.WORD	L89D8	; LFA: previous name field in this vocabulary chain
CCOM:
	.WORD	DOVEC	; CFA: vectored word; dispatch through UP+$32+offset
	.BYTE	18	; Vector byte offset 18 from I/O (UP+$32)

PCCOM:
    .word ccomma_checked

; ---------------------------------------------------------------------------
; Dictionary: - [FORTH].
; Manual stack: ( n1 n2 --- diff )
; Manual: Leaves the difference of n1 minus n2 on the stack.
L89FF:
	.BYTE	$81,$AD
	.WORD	L89EB	; LFA: previous name field in this vocabulary chain
SUBB:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	MINUS
	.WORD	PLUS
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: = [FORTH].
; Manual stack: ( n1 n2 --- f )
; Manual: Leaves a true flag if n1=n2; otherwise leaves a false flag.
L8A0B:
	.BYTE	$81,$BD
	.WORD	L89FF	; LFA: previous name field in this vocabulary chain
EQUAL:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	SUBB
	.WORD	ZEQU
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: U< [FORTH].
; Manual stack: ( u1 u2 --- <f )
; Manual: Compares the two unsigned numbers and leaves a flag representing
; the truth of the statement u1 < u2 on the stack.
L8A17:
	.BYTE	$82,"U",$BC
	.WORD	L8A0B	; LFA: previous name field in this vocabulary chain
ULESS:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 2
	SEC
	LDA	2,X
	SBC	0,X
	LDA	3,X
	SBC	1,X
	INX
	INX
	BCS	L8A33
	LDA	#1
	PHA
	LDA	#0
	JMP	PUT

L8A33:
	LDA	#0
	PHA
	JMP	PUT

; ---------------------------------------------------------------------------
; Dictionary: < [FORTH].
; Manual stack: ( n1 n2 --- f )
; Manual: Leaves a true flag if n1 is less than n2; otherwise leaves a false
; flag.
L8A39:
	.BYTE	$81,$BC
	.WORD	L8A17	; LFA: previous name field in this vocabulary chain
LESS:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 2
	SEC
	LDA	2,X
	SBC	0,X
	LDA	3,X
	SBC	1,X
	STY	3,X
	BVC	L8A4E
	EOR	#$80
L8A4E:
	BPL	L8A51
	INY
L8A51:
	STY	2,X
	JMP	POP

; ---------------------------------------------------------------------------
; Dictionary: > [FORTH].
; Manual stack: ( n1 n2 --- f )
; Manual: Leaves a true flag if n1 is greater than n2; otherwise leaves a
; false flag.
L8A56:
	.BYTE	$81,$BE
	.WORD	L8A39	; LFA: previous name field in this vocabulary chain
GREAT:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	SWAP
	.WORD	LESS
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ROT [FORTH].
; Implementation: ( a b c -- b c a ) Rotate the third cell to the top using
; the return stack temporarily.
L8A62:
	.BYTE	$83,"RO",$D4
	.WORD	L8A56	; LFA: previous name field in this vocabulary chain
ROT:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	TOR
	.WORD	SWAP
	.WORD	RFROM
	.WORD	SWAP
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: SPACE [FORTH].
; Manual: Transmits an ASCII blank to the output device.
L8A74:
	.BYTE	$85,"SPAC",$C5
	.WORD	L8A62	; LFA: previous name field in this vocabulary chain
SPACE:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	BL
	.WORD	EMIT
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: -DUP [FORTH].
; Manual stack: ( n1 --- n1 ) (if zero)
; Manual: ( n1 --- n1 n1 ) (non-zero) Reproduces n1 only if it is non-zero.
; Usually this is used to copy a value just before IF, to eliminate the need
; for an ELSE part to drop it.
L8A84:
	.BYTE	$84,"-DU",$D0
	.WORD	L8A74	; LFA: previous name field in this vocabulary chain
QDUP:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	DUP
	.WORD	ZBRAN,4	; Pop flag; if zero branch to $8A95 (offset +4 from operand cell)
	.WORD	DUP
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: TRAVERSE [FORTH].
; Manual stack: ( a1 n --- a2 )
; Manual: Moves across the name field of the fig-FORTH variable length name
; field. a1 is the address of either length byte or the last letter. If n=1,
; the motion is toward high memory; If n=-1, the motion is toward low memory.
; The a2 resulting is the address of the other end of the name. 147
L8A97:
	.BYTE	$88,"TRAVERS",$C5
	.WORD	L8A84	; LFA: previous name field in this vocabulary chain
TRAV:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	SWAP
	.WORD	OVER
	.WORD	PLUS
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	$7F
	.WORD	OVER
	.WORD	CAT
	.WORD	LESS
	.WORD	ZBRAN,$FFF1	; Pop flag; if zero branch to $8AA6 (offset -15 from operand cell)
	.WORD	SWAP
	.WORD	DROP
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: LATEST [FORTH].
; Manual stack: ( --- a )
; Manual: Leaves the name field address of the topmost word in the CURRENT
; vocabulary.
L8ABD:
	.BYTE	$86,"LATES",$D4
	.WORD	L8A97	; LFA: previous name field in this vocabulary chain
LATES:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	CURR
	.WORD	AT
	.WORD	AT
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: LFA [FORTH].
; Manual stack: ( pfa --- lfa )
; Manual: Converts the parameter field address of a dictionary definition to
; its link address.
L8AD0:
	.BYTE	$83,"LF",$C1
	.WORD	L8ABD	; LFA: previous name field in this vocabulary chain
LFA:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	4
	.WORD	SUBB
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: CFA [FORTH].
; Manual stack: ( pfa --- cfa )
; Manual: Converts the parameter field address of a definition to its code
; field address.
L8ADF:
	.BYTE	$83,"CF",$C1
	.WORD	L8AD0	; LFA: previous name field in this vocabulary chain
CFA:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	TWO
	.WORD	SUBB
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: NFA [FORTH].
; Manual stack: ( pfa --- nfa )
; Manual: Converts the parameter field address of a definition to its name
; field address.
L8AED:
	.BYTE	$83,"NF",$C1
	.WORD	L8ADF	; LFA: previous name field in this vocabulary chain
NFA:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	5
	.WORD	SUBB
    ; Originally .WORD LIT,-1
    .WORD   LIT,$FFFF  ; Push -1: traverse backward through the name
    .WORD   TRAV
    .WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: PFA [FORTH].
; Manual stack: ( nfa --- pfa )
; Manual: Converts the name field address of a compiled definition to its
; parameter field address.
L8B02:
	.BYTE	$83,"PF",$C1
	.WORD	L8AED	; LFA: previous name field in this vocabulary chain
PFA:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	ONE
	.WORD	TRAV
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	5
	.WORD	PLUS
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: !CSP [FORTH].
; Manual: Saves the stack position in CSP. Used as a part of the compiler
; security.
L8B15:
	.BYTE	$84,"!CS",$D0
	.WORD	L8B02	; LFA: previous name field in this vocabulary chain
SCSP:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	SPAT
	.WORD	CSP
	.WORD	STORE
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ?ERROR [FORTH].
; Manual stack: ( f n --- )
; Manual: Issues an error message number, if the boolean flag is true.
L8B26:
	.BYTE	$86,"?ERRO",$D2
	.WORD	L8B15	; LFA: previous name field in this vocabulary chain
QERR:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	SWAP
	.WORD	ZBRAN,4	; Pop flag; if zero branch to $8B39 (offset +4 from operand cell)
	.WORD	ERROR
	.WORD	DROP
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ?COMP [FORTH].
; Manual: Issues an error message if not compiling.
L8B3D:
	.BYTE	$85,"?COM",$D0
	.WORD	L8B26	; LFA: previous name field in this vocabulary chain
QCOMP:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	STATE
	.WORD	AT
	.WORD	ZEQU
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	$11
	.WORD	QERR
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ?EXEC [FORTH].
; Manual: Issues an error message if not executing.
L8B54:
	.BYTE	$85,"?EXE",$C3
	.WORD	L8B3D	; LFA: previous name field in this vocabulary chain
QEXEC:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	STATE
	.WORD	AT
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	$12
	.WORD	QERR
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ?PAIRS [FORTH].
; Implementation: ( actual expected -- ) Compare compiler control markers and
; raise error 19 if unequal.
L8B69:
	.BYTE	$86,"?PAIR",$D3
	.WORD	L8B54	; LFA: previous name field in this vocabulary chain
QPAIR:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	SUBB
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	$13
	.WORD	QERR
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ?CSP [FORTH].
; Manual: Issues an error message if stack position differs from value saved
; in CSP.
L8B7D:
	.BYTE	$84,"?CS",$D0
	.WORD	L8B69	; LFA: previous name field in this vocabulary chain
QCSP:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	SPAT
	.WORD	CSP
	.WORD	AT
	.WORD	SUBB
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	$14
	.WORD	QERR
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ?LOADING [FORTH].
; Manual: Issues an error message if not loading.
L8B95:
	.BYTE	$88,"?LOADIN",$C7
	.WORD	L8B7D	; LFA: previous name field in this vocabulary chain
QLOAD:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	BLK
	.WORD	AT
	.WORD	ZEQU
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	$16
	.WORD	QERR
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: COMPILE [FORTH].
; Manual stack: ( --- )
; Manual: When the word containing COMPILE executes the execution address of
; the word following COMPILE is copied (compiled) into the dictionary. This
; allows specific compilation situations to be handled in addition to simply
; compiling an execution address (which the interpreter has already done).
L8BAF:
	.BYTE	$87,"COMPIL",$C5
	.WORD	L8B95	; LFA: previous name field in this vocabulary chain
COMP:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	QCOMP
	.WORD	RFROM
	.WORD	DUP
	.WORD	TWOP
	.WORD	TOR
	.WORD	AT
	.WORD	COMMA
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: [ [FORTH]; immediate (executes during compilation).
; Manual: Used in a colon-definition in the form: : xxx [words] more ; Leaves
; the compile mode. The words after [ are executed, not compiled. This allows
; calculation or compilation exceptions before resuming compilation with ].
; Called "leftbracket."
L8BCB:
	.BYTE	$C1,$DB
	.WORD	L8BAF	; LFA: previous name field in this vocabulary chain
LBRAC:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	ZERO
	.WORD	STATE
	.WORD	STORE
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ] [FORTH].
; Manual: Resumes compilation to the completion of a colondefinition. See [.
; Called "right bracket."
L8BD9:
	.BYTE	$81,$DD
	.WORD	L8BCB	; LFA: previous name field in this vocabulary chain
RBRAC:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	$C0
	.WORD	STATE
	.WORD	STORE
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: SMUDGE [FORTH].
; Manual: Used during word definition to toggle the "smudge bit" in a
; definitions' name field. This prevents an uncompleted definition from being
; found during dictionary searches, until compiling is completed without
; error.
L8BE8:
	.BYTE	$86,"SMUDG",$C5
	.WORD	L8BD9	; LFA: previous name field in this vocabulary chain
SMUDGE:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	LATES
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	$20
	.WORD	TOGGL
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: HEX [FORTH].
; Manual: Sets the numeric conversion base to sixteen (hexadecimal).
L8BFC:
	.BYTE	$83,"HE",$D8
	.WORD	L8BE8	; LFA: previous name field in this vocabulary chain
HEX:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	$10
	.WORD	BASE
	.WORD	STORE
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: DECIMAL [FORTH].
; Manual: Set the numeric conversion BASE for decimal input-output.
L8C0D:
	.BYTE	$87,"DECIMA",$CC
	.WORD	L8BFC	; LFA: previous name field in this vocabulary chain
DECIM:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	$A
	.WORD	BASE
	.WORD	STORE
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: (;CODE) [FORTH].
; Manual: The run-time procedure, compiled by ;CODE that rewrites the code
; field of the most recently defined word to point to the following machine
; code sequence. See ;CODE.
L8C22:
	.BYTE	$87,"(;CODE",$A9
	.WORD	L8C0D	; LFA: previous name field in this vocabulary chain
PSCOD:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	RFROM
	.WORD	LATES
	.WORD	PFA
	.WORD	CFA
	.WORD	STORE
	.WORD	SEMIS	; Return to caller thread

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
L8C3A:
	.BYTE	$C5,";COD",$C5
	.WORD	L8C22	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	QCSP
	.WORD	COMP
	.WORD	PSCOD	; Inline CFA operand consumed by COMPILE
	.WORD	LBRAC
	.WORD	SMUDGE
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: <BUILDS [FORTH].
; Manual: Used within a colon-definition: : cccc <BUILDS DOES> ... ; Each
; time cccc is executed, <BUILDS defines a new word with a high level
; execution procedure. Executing cccc in the form: cccc nnnn uses <BUILDS to
; create a dictionary entry for nnnn. When nnnn is later executed, it has the
; address of its parameter 109 area on the stack and executes the words after
; DOES> in cccc. <BUILDS and DOES> allow run-time procedures to be written in
; high level rather than in assembler code (as required by ;CODE).
L8C50:
	.BYTE	$87,"<BUILD",$D3
	.WORD	L8C3A	; LFA: previous name field in this vocabulary chain
BUILD:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	ZERO
	.WORD	CONST
	.WORD	SEMIS	; Return to caller thread

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
L8C62:
	.BYTE	$85,"DOES",$BE
	.WORD	L8C50	; LFA: previous name field in this vocabulary chain
DOES:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	RFROM
	.WORD	LATES
	.WORD	PFA
	.WORD	STORE
	.WORD	PSCOD
; DOES> runtime: save caller IP, load the behavior thread address from W+2,
; and push W+4 (the instance data address). Unlike DOCOL, the first parameter
; cell is a behavior pointer.
DODOE:
	LDA	IP+1
	PHA
	LDA	IP
	PHA
	LDY	#2
	LDA	(W),Y
	STA	IP
	INY
	LDA	(W),Y
	STA	IP+1
	CLC
	LDA	W
	ADC	#4
	PHA
	LDA	W+1
	ADC	#0
	JMP	PUSH

; ---------------------------------------------------------------------------
; Dictionary: COUNT [FORTH].
; Manual stack: ( a1 --- a2 n)
; Manual: Leaves the byte address a2 and byte count n of a message text
; beginning at address a1. It is presumed that the first byte at a1 contains
; the text byte count and the actual text starts with the second byte.
; Typically COUNT is followed by TYPE.
L8C94:
	.BYTE	$85,"COUN",$D4
	.WORD	L8C62	; LFA: previous name field in this vocabulary chain
COUNT:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	DUP
	.WORD	ONEP
	.WORD	SWAP
	.WORD	CAT
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: TYPE [FORTH].
; Manual stack: ( a count --- )
; Manual: Transmits count characters from address a, to the selected output
; device.
L8CA8:
	.BYTE	$84,"TYP",$C5
	.WORD	L8C94	; LFA: previous name field in this vocabulary chain
TYPE:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	QDUP
	.WORD	ZBRAN,$1D	; Pop flag; if zero branch to $8CD2 (offset +29 from operand cell)
	.WORD	OVER
	.WORD	PLUS
	.WORD	SWAP
	.WORD	PDO
	.WORD	I
	.WORD	CAT
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	$7F
	.WORD	ANDD
	.WORD	EMIT
	.WORD	PLOOP,$FFF3	; Increment loop index; if continuing branch to $8CBF (offset -13 from operand cell)
	.WORD	BRAN,4	; Jump to $8CD4 (offset +4 from operand cell)
	.WORD	DROP
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: -TRAILING [FORTH].
; Manual stack: ( a n1 --- a n2 )
; Manual: Suppresses the output of trailing blanks, from a text string that
; starts at address a, by adjusting the character count n1. i.e., the
; characters at +n1 to a +n2 are blanks.
L8CD6:
	.BYTE	$89,"-TRAILIN",$C7
	.WORD	L8CA8	; LFA: previous name field in this vocabulary chain
DTRAI:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	DUP
	.WORD	ZERO
	.WORD	PDO
	.WORD	TDUP
	.WORD	PLUS
	.WORD	ONE
	.WORD	SUBB
	.WORD	CAT
	.WORD	BL
	.WORD	SUBB
	.WORD	ZBRAN,8	; Pop flag; if zero branch to $8D02 (offset +8 from operand cell)
	.WORD	LEAVE
	.WORD	BRAN,6	; Jump to $8D06 (offset +6 from operand cell)
	.WORD	ONE
	.WORD	SUBB
	.WORD	PLOOP,$FFE2	; Increment loop index; if continuing branch to $8CEA (offset -30 from operand cell)
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: (.") [FORTH].
; Stack (from code): ( -- ) Consume the inline counted string.
; Manual: The run-time procedure, compiled by ." which transmits the
; following on-line text to the screen or other output device. See ."
L8D0C:
	.BYTE	$84,"(.\"",$A9
	.WORD	L8CD6	; LFA: previous name field in this vocabulary chain
; Runtime of dot-quote: the return IP addresses a count byte and inline text.
; COUNT/TYPE print it; the saved return IP is advanced past the text so those
; bytes are not executed as CFAs.
PDOTQ:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	R
	.WORD	COUNT
	.WORD	DUP
	.WORD	ONEP
	.WORD	RFROM
	.WORD	PLUS
	.WORD	TOR
	.WORD	TYPE
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ." [FORTH]; immediate (executes during compilation).
; Manual: Used in the form: ." cccc" Compiles an in-line string cccc
; (delimited by the trailing quotation mark) with an execution procedure to
; send the text to the selected output device. If executed outside a
; definition, ." will immediately print the text until the closing ". The
; maximum number of characters is 64. See (.") Pronounced "dot quote."
L8D27:
	.BYTE	$C2,".",$A2
	.WORD	L8D0C	; LFA: previous name field in this vocabulary chain
DOTQ:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	"\""
	.WORD	STATE
	.WORD	AT
	.WORD	ZBRAN,$14	; Pop flag; if zero branch to $8D4B (offset +20 from operand cell)
	.WORD	COMP
	.WORD	PDOTQ	; Inline CFA operand consumed by COMPILE
	.WORD	WORD
	.WORD	HERE
	.WORD	CAT
	.WORD	ONEP
	.WORD	ALLOT
	.WORD	BRAN,$A	; Jump to $8D53 (offset +10 from operand cell)
	.WORD	WORD
	.WORD	HERE
	.WORD	COUNT
	.WORD	TYPE
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: EXPECT [FORTH].
; Manual stack: ( a1/n1 --- )
; Manual: Same as fig-FORTH, but uses the Commodore line read routine, which
; can only be terminated by a carriage return at the end of the line. If a
; fig standard version of EXPECT is required, this can be obtained by setting
; EFLAG to value of 1 (one) which causes alternate section of EXPECT code to
; be used.
L8D55:
	.BYTE	$86,"EXPEC",$D4
	.WORD	L8D27	; LFA: previous name field in this vocabulary chain
EXPECT:
    .word expect_serial

; ---------------------------------------------------------------------------
; Dictionary: QUERY [FORTH].
; Manual: Inputs 80 characters of text ( or until a "return") from the
; operators terminal. Text is positioned at the address contained in TIB with
; IN set to zero.
L8DED:
	.BYTE	$85,"QUER",$D9
	.WORD	L8D55	; LFA: previous name field in this vocabulary chain
QUERY:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	TIB
	.WORD	AT
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	127
	.WORD	EXPECT
	.WORD	ZERO
	.WORD	IN
	.WORD	STORE
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: NULL [FORTH]; immediate (executes during compilation).
; Implementation: End-of-input handler for the NUL token. Advance block input
; when loading; otherwise leave the interpreter through its return stack.
L8E08:
	.BYTE	$C1,$80
	.WORD	L8DED	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	BLK
	.WORD	AT
	.WORD	ZBRAN,4	; Pop flag; if zero branch to $8E18 (offset +4 from operand cell)
	.WORD	QEXEC
	.WORD	RFROM
	.WORD	DROP
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: FILL [FORTH].
; Manual stack: ( a quan b --- )
; Manual: Fills memory at the address with the specified quantity of bytes b.
L8E1E:
	.BYTE	$84,"FIL",$CC
	.WORD	L8E08	; LFA: previous name field in this vocabulary chain
FILL:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	SWAP
	.WORD	TOR
	.WORD	OVER
	.WORD	CSTOR
	.WORD	DUP
	.WORD	ONEP
	.WORD	RFROM
	.WORD	ONE
	.WORD	SUBB
	.WORD	CMOVE
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ERASE [FORTH].
; Manual stack: ( a n --- )
; Manual: Clears a region of memory to zero from address 'a' over 'n'
; addresses.
L8E3D:
	.BYTE	$85,"ERAS",$C5
	.WORD	L8E1E	; LFA: previous name field in this vocabulary chain
ERASE:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	ZERO
	.WORD	FILL
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: BLANKS [FORTH].
; Manual stack: ( a count --- )
; Manual: Fills an area of memory beginning at address a with blanks.
L8E4D:
	.BYTE	$86,"BLANK",$D3
	.WORD	L8E3D	; LFA: previous name field in this vocabulary chain
BLANK:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	BL
	.WORD	FILL
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: HOLD [FORTH].
; Manual stack: ( c --- )
; Manual: Used between <# and #> to insert an ASCII character into a pictured
; numeric output string. e.g. 2E HOLD will place a decimal point.
L8E5E:
	.BYTE	$84,"HOL",$C4
	.WORD	L8E4D	; LFA: previous name field in this vocabulary chain
HOLD:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	LIT,$FFFF
	.WORD	HLD
	.WORD	PSTOR
	.WORD	HLD
	.WORD	AT
	.WORD	CSTOR
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: PAD [FORTH].
; Manual stack: ( --- a )
; Manual: Leaves the address of the text output buffer, which is a fixed
; offset above HERE. 137
L8E77:
	.BYTE	$83,"PA",$C4
	.WORD	L8E5E	; LFA: previous name field in this vocabulary chain
PAD:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	HERE
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	68
	.WORD	PLUS
	.WORD	SEMIS	; Return to caller thread

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
L8E88:
	.BYTE	$84,"WOR",$C4
	.WORD	L8E77	; LFA: previous name field in this vocabulary chain
WORD:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	BLK
	.WORD	AT
	.WORD	ZBRAN,$C	; Pop flag; if zero branch to $8EA3 (offset +12 from operand cell)
	.WORD	BLK
	.WORD	AT
	.WORD	BLOCK
	.WORD	BRAN,6	; Jump to $8EA7 (offset +6 from operand cell)
	.WORD	TIB
	.WORD	AT
	.WORD	IN
	.WORD	AT
	.WORD	PLUS
	.WORD	SWAP
	.WORD	ENCL
	.WORD	HERE
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	"\""
	.WORD	BLANK
	.WORD	IN
	.WORD	PSTOR
	.WORD	OVER
	.WORD	SUBB
	.WORD	TOR
	.WORD	R
	.WORD	HERE
	.WORD	CSTOR
	.WORD	PLUS
	.WORD	HERE
	.WORD	ONEP
	.WORD	RFROM
	.WORD	CMOVE
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: (NUMBER) [FORTH].
; Manual stack: (d1 a1 --- d2 a2 )
; Manual: Converts the ASCII text beginning at a1+1 using the current numeric
; BASE. The new value is accumulated into double number d1, being left as d2.
; a2 is the address of the first unconvertible digit. Used by NUMBER.
L8ED4:
	.BYTE	$88,"(NUMBER",$A9
	.WORD	L8E88	; LFA: previous name field in this vocabulary chain
PNUMB:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	ONEP
	.WORD	DUP
	.WORD	TOR
	.WORD	CAT
	.WORD	BASE
	.WORD	AT
	.WORD	DIGIT
	.WORD	ZBRAN,$2C	; Pop flag; if zero branch to $8F1D (offset +44 from operand cell)
	.WORD	SWAP
	.WORD	BASE
	.WORD	AT
	.WORD	USTAR
	.WORD	DROP
	.WORD	ROT
	.WORD	BASE
	.WORD	AT
	.WORD	USTAR
	.WORD	DPLUS
	.WORD	DPL
	.WORD	AT
	.WORD	ONEP
	.WORD	ZBRAN,8	; Pop flag; if zero branch to $8F17 (offset +8 from operand cell)
	.WORD	ONE
	.WORD	DPL
	.WORD	PSTOR
	.WORD	RFROM
	.WORD	BRAN,$FFC6	; Jump to $8EE1 (offset -58 from operand cell)
	.WORD	RFROM
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: NUMBER [FORTH].
; Manual stack: ( a --- d )
; Manual: Converts a character string left at address a with a preceeding
; count to a signed double number using the current numeric base. If a
; decimal point is encountered in the text, its position will be given in
; DPL, but no other effect occurs. If numeric conversion is not possible, an
; error message will be given. This is a vectored word.
L8F21:
	.BYTE	$86,"NUMBE",$D2
	.WORD	L8ED4	; LFA: previous name field in this vocabulary chain
NUMBER:
	.WORD	DOVEC	; CFA: vectored word; dispatch through UP+$32+offset
	.BYTE	10	; Vector byte offset 10 from I/O (UP+$32)

PNUMBE:
	.WORD	DOCOL
	.WORD	ZERO
	.WORD	ZERO
	.WORD	ROT
	.WORD	DUP
	.WORD	ONEP
	.WORD	CAT
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	"-"
	.WORD	EQUAL
	.WORD	DUP
	.WORD	TOR
	.WORD	PLUS
	.WORD	LIT,$FFFF
	.WORD	DPL
	.WORD	STORE
	.WORD	PNUMB
	.WORD	DUP
	.WORD	CAT
	.WORD	BL
	.WORD	SUBB
	.WORD	ZBRAN,$15	; Pop flag; if zero branch to $8F6F (offset +21 from operand cell)
	.WORD	DUP
	.WORD	CAT
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	"."
	.WORD	SUBB
	.WORD	ZERO
	.WORD	QERR
	.WORD	ZERO
	.WORD	BRAN,$FFDD	; Jump to $8F4A (offset -35 from operand cell)
	.WORD	DROP
	.WORD	RFROM
	.WORD	ZBRAN,4	; Pop flag; if zero branch to $8F79 (offset +4 from operand cell)
	.WORD	DMINU
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: -FIND [FORTH].
; Manual stack: ( --- pfa b tf ) (found)
; Manual: ( --- ff ) (not found) Accepts the next text word (delimited by
; blanks) in the input stream to HERE, and searches the CONTEXT and then the
; CURRENT vocabularies for a matching entry. If found, the dictionary entry's
; parameter field address, its length in bytes, and a boolean true is left.
; Otherwise, only a boolean false is left. This is a vectored word.
L8F7B:
	.BYTE	$85,"-FIN",$C4
	.WORD	L8F21	; LFA: previous name field in this vocabulary chain
DFIND:
	.WORD	DOVEC	; CFA: vectored word; dispatch through UP+$32+offset
	.BYTE	16	; Vector byte offset 16 from I/O (UP+$32)

PDFIND:
	.WORD	DOCOL
	.WORD	BL
	.WORD	WORD
	.WORD	UPPER_TOKEN
	.WORD	HERE
	.WORD	CONT
	.WORD	AT
	.WORD	AT
	.WORD	PFIND
	.WORD	DUP
	.WORD	ZEQU
	.WORD	ZBRAN,$A	; Pop flag; if zero branch to $8FA6 (offset +10 from operand cell)
	.WORD	DROP
	.WORD	HERE
	.WORD	LATES
	.WORD	PFIND
	.WORD	SEMIS	; Return to caller thread

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
L8FA8:
	.BYTE	$85,"ERRO",$D2
	.WORD	L8F7B	; LFA: previous name field in this vocabulary chain
ERROR:
	.WORD	DOVEC	; CFA: vectored word; dispatch through UP+$32+offset
	.BYTE	12	; Vector byte offset 12 from I/O (UP+$32)

PERROR:
    .word *+2
    lda 0,x
    jmp shell_error

; ---------------------------------------------------------------------------
;	ERROR MESSAGES
; ---------------------------------------------------------------------------
; Error-number table: cells point at counted error strings below. MESSAGE
; selects one by index; these .WORD values are addresses, not executable
; threads.
L8FD2:
	.WORD	L9006
	.WORD	L900B
	.WORD	L9018
	.WORD	L9034
	.WORD	L9026
	.WORD	L9026
	.WORD	L9026
	.WORD	L9026
	.WORD	L9046
	.WORD	L9026
	.WORD	L9026
	.WORD	L9026
	.WORD	L9026
	.WORD	L9026
	.WORD	L9026
	.WORD	L9026
	.WORD	L9026
	.WORD	L9058
	.WORD	L906B
	.WORD	L907E
	.WORD	L9094
	.WORD	L90AA
	.WORD	L90BE
	.WORD	L9026
	.WORD	L90D4
	.WORD	L9026
ERR_NO_C64_SLOT:
    .WORD   ERR_NO_C64
    .word ERR_STACK_FULL, ERR_RX_FULL, ERR_RETURN_FULL, ERR_BREAK, ERR_DIV_ZERO, ERR_LINE_LONG
ERROR_TABLE_END:

L9006:
	.BYTE	4
	.BYTE	"WHAT"
L900B:
	.BYTE	12
	.BYTE	"STACK EMPTY!"
L9018:
	.BYTE	13
	.BYTE	"OUT OF MEMORY"
L9026:
	.BYTE	13
	.BYTE	"UNKNOWN ERROR"
L9034:
	.BYTE	17
	.BYTE	"HAS BAD ADDR MODE"
L9046:
	.BYTE	17
	.BYTE	"BLOCK RANGE ERROR"
L9058:
	.BYTE	18
	.BYTE	"FOR COMPILING ONLY"
L906B:
	.BYTE	18
	.BYTE	"FOR EXECUTING ONLY"
L907E:
	.BYTE	21
	.BYTE	"IMPROPER CONDITIONALS"
L9094:
	.BYTE	21
	.BYTE	"INCOMPLETE DEFINITION"
L90AA:
	.BYTE	19
	.BYTE	"THIS WORD PROTECTED"
L90BE:
	.BYTE	21
	.BYTE	"USE ONLY WHEN LOADING"
L90D4:
	.BYTE	22
	.BYTE	"SPECIFY THE VOCABULARY"
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
L90EB:
	.BYTE	$83,"ID",$AE
	.WORD	L8FA8	; LFA: previous name field in this vocabulary chain
IDDOT:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	COUNT
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	$1F
	.WORD	ANDD
	.WORD	TYPE
	.WORD	SPACE
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: CREATE [FORTH].
; Manual: A defining word used in the form: CREATE cccc by such words as CODE
; and CONSTANT to create a dictionary header for a FORTH definition. The code
; field contains the address of the word's parameter field. The new word is
; created in the CURRENT vocabulary. This is a vectored word.
L9100:
	.BYTE	$86,"CREAT",$C5
	.WORD	L90EB	; LFA: previous name field in this vocabulary chain
CREAT:
	.WORD	DOVEC	; CFA: vectored word; dispatch through UP+$32+offset
	.BYTE	8	; Vector byte offset 8 from I/O (UP+$32)

; Construct a RAM dictionary header at HERE: copy the parsed name, enforce
; WIDTH, mark name end and header flag bits, link to LATEST, and allocate the
; initial code/parameter fields. SMUDGE hides a definition while it is being
; built.
PCREAT:
	.WORD	DOCOL
	.WORD	DFIND
	.WORD	ZBRAN,$14	; Pop flag; if zero branch to $9126 (offset +20 from operand cell)
	.WORD	DROP
	.WORD	CR
	.WORD	PDOTQ	; Print counted inline text; resume after its payload
	.BYTE	7
	.BYTE	"REDEF: "
	.WORD	NFA
	.WORD	IDDOT
	.WORD	HERE
	.WORD	DUP
	.WORD	CAT
	.WORD	WIDTH
	.WORD	AT
	.WORD	MIN
	.WORD	ONEP
	.WORD	ALLOT
	.WORD	DUP
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	$A0
	.WORD	TOGGL
	.WORD	HERE
	.WORD	ONE
	.WORD	SUBB
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	$80
	.WORD	TOGGL
	.WORD	LATES
	.WORD	COMMA
	.WORD	CURR
	.WORD	AT
	.WORD	STORE
	.WORD	HERE
	.WORD	TWOP
	.WORD	COMMA
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: [COMPILE] [FORTH]; immediate (executes during compilation).
; Manual: Used in a colon-definition In the form: : xxx [COMPILE] FORTH ;
; [COMPILE] will force the compilation of an Immediate definition that would
; otherwise execute during compilation. The above example will select the
; FORTH vocabulary when xxx executes, rather than at compile time.
L915A:
	.BYTE	$C9,"[COMPILE",$DD
	.WORD	L9100	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	DFIND
	.WORD	ZEQU
	.WORD	ZERO
	.WORD	QERR
	.WORD	DROP
	.WORD	CFA
	.WORD	COMMA
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: LITERAL [FORTH]; immediate (executes during compilation).
; Manual stack: ( n --- ) (compiling)
; Manual: At compile-time, the LITERAL compiles the stack value n as a 16-bit
; literal. This definition is immediate so that it will execute during a
; colon-definition. The intended use is: xxx (calculate) LITERAL 133
; Compilation is suspended for the compile time calculation of a value.
; Compilation is resumed and LITERAL compiles this value. At run-time, the
; value will be pushed onto the stack.
L9178:
	.BYTE	$C7,"LITERA",$CC
	.WORD	L915A	; LFA: previous name field in this vocabulary chain
LITER:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	STATE
	.WORD	AT
	.WORD	ZBRAN,8	; Pop flag; if zero branch to $9192 (offset +8 from operand cell)
	.WORD	COMP
	.WORD	LIT,COMMA	; First CFA is consumed by COMPILE; remaining cells resume the thread
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: DLITERAL [FORTH]; immediate (executes during compilation).
; Manual stack: ( d --- d ) (executing)
; Manual: ( d --- d ) (compiling) If compiling, compiles a stack double
; number into a literal. Later execution of this definition containing the
; literal will push it to the stack. If executing, the number remains on the
; stack.
L9194:
	.BYTE	$C8,"DLITERA",$CC
	.WORD	L9178	; LFA: previous name field in this vocabulary chain
DLIT:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	STATE
	.WORD	AT
	.WORD	ZBRAN,8	; Pop flag; if zero branch to $91AF (offset +8 from operand cell)
	.WORD	SWAP
	.WORD	LITER
	.WORD	LITER
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ?STACK [FORTH].
; Manual: Issues an error message if the stack is out of bounds.
L91B1:
	.BYTE	$86,"?STAC",$CB
	.WORD	L9194	; LFA: previous name field in this vocabulary chain
QSTAC:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	SPAT
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	TOS
	.WORD	SWAP
	.WORD	ULESS
	.WORD	ONE
	.WORD	QERR
	.WORD	EM
	.WORD	AT
	.WORD	HERE
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	$A0
	.WORD	PLUS
	.WORD	ULESS
	.WORD	TWO
	.WORD	QERR
	.WORD	SEMIS	; Return to caller thread

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
L91DC:
	.BYTE	$89,"INTERPRE",$D4
	.WORD	L91B1	; LFA: previous name field in this vocabulary chain
; OUTER INTERPRETER. Parse/search with -FIND. A found word is compiled or
; executed according to STATE and header immediacy. Otherwise NUMBER converts
; it; DPL distinguishes single/double literals. ?STACK validates the
; resulting data-stack position before continuing.
INTER:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	DFIND
	.WORD	ZBRAN,$1E	; Pop flag; if zero branch to $920C (offset +30 from operand cell)
	.WORD	STATE
	.WORD	AT
	.WORD	LESS
	.WORD	ZBRAN,$A	; Pop flag; if zero branch to $9202 (offset +10 from operand cell)
	.WORD	CFA
	.WORD	COMMA
	.WORD	BRAN,6	; Jump to $9206 (offset +6 from operand cell)
	.WORD	CFA
	.WORD	EXEC
	.WORD	QSTAC
	.WORD	BRAN,$1C	; Jump to $9226 (offset +28 from operand cell)
	.WORD	HERE
	.WORD	NUMBER
	.WORD	DPL
	.WORD	AT
	.WORD	ONEP
	.WORD	ZBRAN,8	; Pop flag; if zero branch to $9220 (offset +8 from operand cell)
	.WORD	DLIT
	.WORD	BRAN,6	; Jump to $9224 (offset +6 from operand cell)
	.WORD	DROP
	.WORD	LITER
	.WORD	QSTAC
	.WORD	BRAN,$FFC2	; Jump to $91EA (offset -62 from operand cell)

; ---------------------------------------------------------------------------
; Dictionary: IMMEDIATE [FORTH].
; Manual: Marks the most recently made definition so that when encountered at
; compile time, it will be executed rather than being complied, that is, the
; precedence bit in its 131 header is set. This method allows definitions to
; handle unusual compiling situations, rather than build them into the
; fundamental compiler. The user may force compilation of an IMMEDIATE
; definition by preceeding it with [COMPILE].
L922A:
	.BYTE	$89,"IMMEDIAT",$C5
	.WORD	L91DC	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	LATES
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	$40
	.WORD	TOGGL
	.WORD	SEMIS	; Return to caller thread

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
L9241:
	.BYTE	$8A,"VOCABULAR",$D9
	.WORD	L922A	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	BUILD
	.WORD	LIT,$A081
	.WORD	COMMA
	.WORD	CURR
	.WORD	AT
	.WORD	CFA
	.WORD	COMMA
	.WORD	HERE
	.WORD	VOCL
	.WORD	AT
	.WORD	COMMA
	.WORD	VOCL
	.WORD	STORE
	.WORD	DOES
DOVOC:
	.WORD	TWOP
	.WORD	CONT
	.WORD	STORE
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: DEFINITIONS [FORTH].
; Manual stack: ( --- )
; Manual: Used in the form: cccc DEFINITIONS Sets the current vocabulary to
; the CONTEXT vocabulary. In the example, executing vocabulary name cccc made
; it the CONTEXT vocabulary and executing DEFINITIONS made both specify
; vocabulary cccc.
L9276:
	.BYTE	$8B,"DEFINITION",$D3
	.WORD	L9241	; LFA: previous name field in this vocabulary chain
DEFIN:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	CONT
	.WORD	AT
	.WORD	CURR
	.WORD	STORE
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ( [FORTH]; immediate (executes during compilation).
; Manual: Used in the form: ( cccc ) Encloses explanatory comments which will
; be ignored by the computer. Delimited by a right parenthesis on the 102
; same line. May occur during execution or in a colondefinition. A blank
; after the leading parenthesis is required. Pronounced 1eft paren."
L9290:
	.BYTE	$C1,$A8
	.WORD	L9276	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	")"
	.WORD	WORD
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: QUIT [FORTH].
; Manual: Clears the return stack. Stops compilation, and returns control to
; the operator's terminal. No message is given.
L929D:
	.BYTE	$84,"QUI",$D4
	.WORD	L9290	; LFA: previous name field in this vocabulary chain
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
L92CF:
	.BYTE	$85,"ABOR",$D4
	.WORD	L929D	; LFA: previous name field in this vocabulary chain
ABORT:
    .word shell_abort

; Native cold-thread entry: point IP directly at COLD1 (the parameter
; thread), bypassing the COLD CFA.
L936B:
	LDA	#>COLD1
	STA	IP+1
	LDA	#<COLD1
	JMP	L937A

; Native warm-thread entry: point IP at WARM. Both starts clear decimal mode
; and reset the hardware/data stack pointers before NEXT.
L9374:
	LDA	#>WARM
	STA	IP+1
	LDA	#<WARM
; Common restart: install IP low byte and reset native/Forth stack state.
L937A:
	STA	IP
	CLD
	LDX	#$FF
	TXS
	LDX	#TOS
	JMP	NEXT

; ROM checksum descriptor. Sum bytes in [L8000,L9385) modulo 65536 and
; compare to $83E4. The descriptor and later ROM code are not in this range.
; Preserve these bytes when adding annotations.
L9385:
	.WORD	L8000		; CHECKSUM START ADDR
L9387:
	.WORD	L9385		; CHECKSUM END ADDR + 1
L9389:
	.WORD	$83E4		; CHECKSUM

; ---------------------------------------------------------------------------
; Dictionary: COLD [FORTH].
; IMNOTWOPR: implemented by the serial shell.
; Original C64 manual stack: ( --- )
; Manual: The COLD start procedure adjusts the dictionary pointer to the
; minimum standard and restarts via ABORT. May be called from the terminal to
; remove application programs and restart. See EMPTY.
L938B:
	.BYTE	$84,"COL",$C4
	.WORD	L92CF	; LFA: previous name field in this vocabulary chain
COLD:
L93E7:
L9436:
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
L9451:
	.BYTE	$85,"EMPT",$D9
	.WORD	L938B	; LFA: previous name field in this vocabulary chain
; Restore the 78-byte vocabulary template at LA955 into RAM at $0840 and set
; DP=$1000. Execute the RAM FORTH vocabulary and DEFINITIONS to restore both
; search and compilation vocabularies, then return.
EMPTY:
    .word shell_empty

; ===========================================================================
; SIGNED ARITHMETIC, CONTROL COMPILATION AND NUMBER FORMATTING
; ===========================================================================

; ---------------------------------------------------------------------------
; Dictionary: S->D [FORTH].
; Manual stack: ( n --- d )
; Manual: Sign extend a single number to form a double number.
L9477:
	.BYTE	$84,"S->",$C4
	.WORD	L9451	; LFA: previous name field in this vocabulary chain
STOD:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	DUP
	.WORD	ZLESS
	.WORD	MINUS
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: +- [FORTH].
; Manual stack: ( n1 n2 --- n3 )
; Manual: Applies the sign of n2 to n1, which is left as n3.
L9488:
	.BYTE	$82,"+",$AD
	.WORD	L9477	; LFA: previous name field in this vocabulary chain
PM:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	ZLESS
	.WORD	ZBRAN,4	; Pop flag; if zero branch to $9497 (offset +4 from operand cell)
	.WORD	MINUS
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: D+- [FORTH].
; Manual stack: ( d1 n --- d2 )
; Manual: Applies the sign of n to the double number d1, leaving it as d2.
L9499:
	.BYTE	$83,"D+",$AD
	.WORD	L9488	; LFA: previous name field in this vocabulary chain
DPM:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	ZLESS
	.WORD	ZBRAN,4	; Pop flag; if zero branch to $94A9 (offset +4 from operand cell)
	.WORD	DMINU
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ABS [FORTH].
; Manual stack: ( n --- u )
; Manual: Leaves the absolute value of n as u.
L94AB:
	.BYTE	$83,"AB",$D3
	.WORD	L9499	; LFA: previous name field in this vocabulary chain
ABS:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	DUP
	.WORD	PM
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: DABS [FORTH].
; Manual stack: ( d --- ud )
; Manual: Leaves the absolute value ud of a double number.
L94B9:
	.BYTE	$84,"DAB",$D3
	.WORD	L94AB	; LFA: previous name field in this vocabulary chain
DABS:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	DUP
	.WORD	DPM
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: MIN [FORTH].
; Manual stack: ( n1 n2 --- min )
; Manual: Leaves the smaller of two numbers.
L94C8:
	.BYTE	$83,"MI",$CE
	.WORD	L94B9	; LFA: previous name field in this vocabulary chain
MIN:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	TDUP
	.WORD	GREAT
	.WORD	ZBRAN,4	; Pop flag; if zero branch to $94DA (offset +4 from operand cell)
	.WORD	SWAP
	.WORD	DROP
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: MAX [FORTH].
; Manual stack: ( n1 n2 --- max)
; Manual: Leaves the greatest of two numbers.
L94DE:
	.BYTE	$83,"MA",$D8
	.WORD	L94C8	; LFA: previous name field in this vocabulary chain
MAX:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	TDUP
	.WORD	LESS
	.WORD	ZBRAN,4	; Pop flag; if zero branch to $94F0 (offset +4 from operand cell)
	.WORD	SWAP
	.WORD	DROP
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: M* [FORTH].
; Manual stack: ( n1 n2 --- d )
; Manual: A mixed magnitude math operation which leaves the double number
; signed product of two signed numbers.
L94F4:
	.BYTE	$82,"M",$AA
	.WORD	L94DE	; LFA: previous name field in this vocabulary chain
MSTAR:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	TDUP
	.WORD	XORR
	.WORD	TOR
	.WORD	ABS
	.WORD	SWAP
	.WORD	ABS
	.WORD	USTAR
	.WORD	RFROM
	.WORD	DPM
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: M/ [FORTH].
; Manual stack: ( d n1 --- n2 n3 )
; Manual: A mixed magnitude math operator which leaves the signed remainder
; of n2 and signed quotient n3 from a double number dividend and divisor n1.
; The remainder takes its sign from the dividend.
L950F:
	.BYTE	$82,"M",$AF
	.WORD	L94F4	; LFA: previous name field in this vocabulary chain
MSLAS:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	OVER
	.WORD	TOR
	.WORD	TOR
	.WORD	DABS
	.WORD	R
	.WORD	ABS
	.WORD	USLAS
	.WORD	RFROM
	.WORD	R
	.WORD	XORR
	.WORD	PM
	.WORD	SWAP
	.WORD	RFROM
	.WORD	PM
	.WORD	SWAP
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: * [FORTH].
; Manual stack: ( n1 n2 --- prod )
; Manual: Leaves the signed product of two signed numbers on the stack. Use .
; (dot) to print the result.
L9536:
	.BYTE	$81,$AA
	.WORD	L950F	; LFA: previous name field in this vocabulary chain
STAR:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	USTAR
	.WORD	DROP
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: /MOD [FORTH].
; Manual stack: ( n1 n2 --- rem quot )
; Manual: Leaves the remainder and signed quotient of n1/n2. The remainder
; has the sign of the dividend.
L9542:
	.BYTE	$84,"/MO",$C4
	.WORD	L9536	; LFA: previous name field in this vocabulary chain
SLMOD:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	TOR
	.WORD	STOD
	.WORD	RFROM
	.WORD	MSLAS
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: / [FORTH].
; Manual stack: ( n1 n2 --- quot )
; Manual: Leaves the signed quotient of n1/n2.
L9555:
	.BYTE	$81,$AF
	.WORD	L9542	; LFA: previous name field in this vocabulary chain
SLASH:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	SLMOD
	.WORD	SWAP
	.WORD	DROP
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: MOD [FORTH].
; Manual stack: ( n1 n2 ---mod )
; Manual: Leaves the remainder of n1/n2, with the same sign as n1.
L9563:
	.BYTE	$83,"MO",$C4
	.WORD	L9555	; LFA: previous name field in this vocabulary chain
MOD:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	SLMOD
	.WORD	DROP
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: */MOD [FORTH].
; Manual stack: ( n1 n2 n3 --- n4 n5 )
; Manual: Leaves the quotient n5 and remainder n4 of the operation n1*n2/n3
; on the stack. A 31-bit intermediate product is used as for */.
L9571:
	.BYTE	$85,"*/MO",$C4
	.WORD	L9563	; LFA: previous name field in this vocabulary chain
SSMOD:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	TOR
	.WORD	MSTAR
	.WORD	RFROM
	.WORD	MSLAS
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: */ [FORTH].
; Manual stack: ( n1 n2 n3 --- n4)
; Manual: Leaves the ratio n4=n1*n2/n3 where all are assigned 105 numbers.
; Retention of an intermediate 31-bit product permits greater accuracy than
; would be available with the sequence: n1 n2 * n3 /
L9585:
	.BYTE	$82,"*",$AF
	.WORD	L9571	; LFA: previous name field in this vocabulary chain
SSLAS:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	SSMOD
	.WORD	SWAP
	.WORD	DROP
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: M/MOD [FORTH].
; Manual stack: ( ud1 u2 --- u3 ud4)
; Manual: An unsigned mixed magnitude math operation which leaves a double
; quotient ud4 and remainder u3, from a double dividend u1 and single divisor
; u2.
L9594:
	.BYTE	$85,"M/MO",$C4
	.WORD	L9585	; LFA: previous name field in this vocabulary chain
MSLM:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	TOR
	.WORD	ZERO
	.WORD	R
	.WORD	USLAS
	.WORD	RFROM
	.WORD	SWAP
	.WORD	TOR
	.WORD	USLAS
	.WORD	RFROM
	.WORD	SEMIS	; Return to caller thread

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
L95B2:
	.BYTE	$85,"BLOC",$CB
	.WORD	L9594	; LFA: previous name field in this vocabulary chain
BLOCK:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: (LINE) [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 n2 --- a count )
; Manual: Converts the line number n1 and the screen n2 to the disk buffers
; address containing the data. A count of 64 indicates the full fine text
; length.
L95C4:
	.BYTE	$86,"(LINE",$A9
	.WORD	L95B2	; LFA: previous name field in this vocabulary chain
PLINE:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: .LINE [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1/n2 --- )
; Manual: Prints on the terminal device, a line of text from the disk or
; cassette by its line and screen numbers. Trailing blanks are suppressed.
L95E3:
	.BYTE	$85,".LIN",$C5
	.WORD	L95C4	; LFA: previous name field in this vocabulary chain
DLINE:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: MESSAGE [FORTH].
; Manual stack: ( n1 --- )
; Manual: Prints the error message number n1 to the current output device.
; 64FORTH prints the error messages from ROM memory, and not from disk.
L95F5:
	.BYTE	$87,"MESSAG",$C5
	.WORD	L95E3	; LFA: previous name field in this vocabulary chain
MESS:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	(ERROR_TABLE_END-L8FD2)/2-1
	.WORD	MIN
	.WORD	ZERO
	.WORD	MAX
	.WORD	TWO
	.WORD	STAR
	.WORD	LIT,L8FD2
	.WORD	PLUS
	.WORD	AT
	.WORD	COUNT
	.WORD	TYPE
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: LOAD [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n --- )
; Manual: Begins interpretation of screen n. Loading will terminate at the
; end of screen or at ;S. See ;S and -->
L961C:
	.BYTE	$84,"LOA",$C4
	.WORD	L95F5	; LFA: previous name field in this vocabulary chain
LOAD:
    .word NO_C64
L964F:
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
L965D:
	.BYTE	$C1,$A7
	.WORD	L961C	; LFA: previous name field in this vocabulary chain
TICK:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	DFIND
	.WORD	ZEQU
	.WORD	ZERO
	.WORD	QERR
	.WORD	DROP
	.WORD	LITER
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: BACK [FORTH].
; Manual stack: ( a --- )
; Manual: Calculates the backward branch offset from HERE to address 2, and
; compiles into the next available dictionary memory address.
L9671:
	.BYTE	$84,"BAC",$CB
	.WORD	L965D	; LFA: previous name field in this vocabulary chain
BACK:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	HERE
	.WORD	SUBB
	.WORD	COMMA
	.WORD	SEMIS	; Return to caller thread

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
L9682:
	.BYTE	$C5,"BEGI",$CE
	.WORD	L9671	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	QCOMP
	.WORD	HERE
	.WORD	ONE
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: ENDIF [FORTH]; immediate (executes during compilation).
; Manual stack: ( a n --- ) (compile)
; Manual: Occurs in a colon-definition in the form: IF...ELSE...ENDIF
; IF...ENDIF At run-time, ENDIF serves only as the destination of a forward
; branch from IF or ELSE. It marks the conclusion of the conditional
; structure. THEN is another name for ENDIF. See also IF and ELSE.
L9694:
	.BYTE	$C5,"ENDI",$C6
	.WORD	L9682	; LFA: previous name field in this vocabulary chain
ENDIF:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	QCOMP
	.WORD	TWO
	.WORD	QPAIR
	.WORD	HERE
	.WORD	OVER
	.WORD	SUBB
	.WORD	SWAP
	.WORD	STORE
	.WORD	SEMIS	; Return to caller thread

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
L96B0:
	.BYTE	$C2,"D",$CF
	.WORD	L9694	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	COMP
	.WORD	PDO	; Inline CFA operand consumed by COMPILE
	.WORD	HERE
	.WORD	THREE
	.WORD	SEMIS	; Return to caller thread

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
L96C1:
	.BYTE	$C4,"LOO",$D0
	.WORD	L96B0	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	THREE
	.WORD	QPAIR
	.WORD	COMP
	.WORD	PLOOP	; Inline CFA operand consumed by COMPILE
	.WORD	BACK
	.WORD	SEMIS	; Return to caller thread

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
L96D6:
	.BYTE	$C5,"+LOO",$D0
	.WORD	L96C1	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	THREE
	.WORD	QPAIR
	.WORD	COMP
	.WORD	PPLOO	; Inline CFA operand consumed by COMPILE
	.WORD	BACK
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: UNTIL [FORTH]; immediate (executes during compilation).
; Manual stack: ( f --- ) (run-time)
; Manual: ( a n --- ) (compile) Occurs within a colon-definition in the form:
; BEGIN ... UNTIL 148 At run-time, UNTIL controls the conditional branch back
; to the corresponding BEGIN. If f is false, execution returns to just after
; BEGIN; if true execution continues ahead. At compile-time, UNTIL compiles
; (0BRANCH) and an offset from HERE to address n is used for error testing.
L96EC:
	.BYTE	$C5,"UNTI",$CC
	.WORD	L96D6	; LFA: previous name field in this vocabulary chain
UNTIL:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	ONE
	.WORD	QPAIR
	.WORD	COMP
	.WORD	ZBRAN,BACK	; First CFA is consumed by COMPILE; remaining cells resume the thread
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: AGAIN [FORTH]; immediate (executes during compilation).
; Manual stack: ( a n --- ) (compiling)
; Manual: Used in a colon-definition in the form: BEGIN ... AGAIN At
; run-time, AGAIN forces execution to return to the corresponding BEGIN.
; There is no effect on the stack. Execution can be terminated by pressing
; the RUN/STOP and RESTORE keys simultaneously.
L9702:
	.BYTE	$C5,"AGAI",$CE
	.WORD	L96EC	; LFA: previous name field in this vocabulary chain
AGAIN:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	ONE
	.WORD	QPAIR
	.WORD	COMP
	.WORD	BRAN	; Inline CFA operand consumed by COMPILE
	.WORD	BACK
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: REPEAT [FORTH]; immediate (executes during compilation).
; Manual stack: ( a n --- ) (compiling)
; Manual: Used with a colon-definition in the form: BEGIN ... WHILE ...
; REPEAT At run-time, REPEAT forces an unconditional branch back to just
; after the corresponding BEGIN. At compile-time, REPEAT compiles BRANCH and
; the offset from HERE to address n is used for error testing.
L9718:
	.BYTE	$C6,"REPEA",$D4
	.WORD	L9702	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	TOR
	.WORD	TOR
	.WORD	AGAIN
	.WORD	RFROM
	.WORD	RFROM
	.WORD	TWO
	.WORD	SUBB
	.WORD	ENDIF
	.WORD	SEMIS	; Return to caller thread

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
L9735:
	.BYTE	$C2,"I",$C6
	.WORD	L9718	; LFA: previous name field in this vocabulary chain
IF:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	COMP
	.WORD	ZBRAN,HERE	; First CFA is consumed by COMPILE; remaining cells resume the thread
	.WORD	ZERO
	.WORD	COMMA
	.WORD	TWO
	.WORD	SEMIS	; Return to caller thread

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
L974A:
	.BYTE	$C4,"ELS",$C5
	.WORD	L9735	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	TWO
	.WORD	QPAIR
	.WORD	COMP
	.WORD	BRAN	; Inline CFA operand consumed by COMPILE
	.WORD	HERE
	.WORD	ZERO
	.WORD	COMMA
	.WORD	SWAP
	.WORD	TWO
	.WORD	ENDIF
	.WORD	TWO
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: WHILE [FORTH]; immediate (executes during compilation).
; Implementation: Compilation: compile IF after the BEGIN destination, then
; rearrange control markers for REPEAT.
L976B:
	.BYTE	$C5,"WHIL",$C5
	.WORD	L974A	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	IF
	.WORD	TWOP
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: SPACES [FORTH].
; Manual stack: ( n --- )
; Manual: Transmits n ASCII blanks to the output device.
L977B:
	.BYTE	$86,"SPACE",$D3
	.WORD	L976B	; LFA: previous name field in this vocabulary chain
SPACS:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	ZERO
	.WORD	MAX
	.WORD	QDUP
	.WORD	ZBRAN,$C	; Pop flag; if zero branch to $979A (offset +12 from operand cell)
	.WORD	ZERO
	.WORD	PDO
	.WORD	SPACE
	.WORD	PLOOP,$FFFC	; Increment loop index; if continuing branch to $9794 (offset -4 from operand cell)
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: <# [FORTH].
; Manual: Begins the number conversion for formatting using the words: <# #
; #S #>. The conversion is done on a double number producing text at PAD.
L979C:
	.BYTE	$82,"<",$A3
	.WORD	L977B	; LFA: previous name field in this vocabulary chain
BDIGS:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	PAD
	.WORD	HLD
	.WORD	STORE
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: #> [FORTH].
; Manual stack: ( d --- a count )
; Manual: Terminates numeric output conversion by dropping d, leaving the
; text address and character count suitable for TYPE.
L97AB:
	.BYTE	$82,"#",$BE
	.WORD	L979C	; LFA: previous name field in this vocabulary chain
EDIGS:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	DROP
	.WORD	DROP
	.WORD	HLD
	.WORD	AT
	.WORD	PAD
	.WORD	OVER
	.WORD	SUBB
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: SIGN [FORTH].
; Manual stack: ( n d --- d )
; Manual: Stores an ASCII "-" sign just before a converted numeric output
; string in the text output buffer when n is negative. N is discarded but
; double number d is maintained. Must be used between <# and #>.
L97C2:
	.BYTE	$84,"SIG",$CE
	.WORD	L97AB	; LFA: previous name field in this vocabulary chain
SIGN:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	ROT
	.WORD	ZLESS
	.WORD	ZBRAN,7	; Pop flag; if zero branch to $97D8 (offset +7 from operand cell)
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	"-"
	.WORD	HOLD
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: # [FORTH].
; Manual stack: ( d1 --- d2 )
; Manual: Generates from a double number d1, the next ASCII character placed
; in an output string. Result d2 is the quotient after division by BASE, and
; is maintained for further processing. Used between <# and #>. See #S. 101
L97DA:
	.BYTE	$81,$A3
	.WORD	L97C2	; LFA: previous name field in this vocabulary chain
DIG:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	BASE
	.WORD	AT
	.WORD	MSLM
	.WORD	ROT
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	9
	.WORD	OVER
	.WORD	LESS
	.WORD	ZBRAN,7	; Pop flag; if zero branch to $97F8 (offset +7 from operand cell)
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	7
	.WORD	PLUS
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	"0"
	.WORD	PLUS
	.WORD	HOLD
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; Dictionary: #S [FORTH].
; Stack (from code): ( ud -- 0 0 )
; Manual: Generates ASCII text in the text output buffer, by the use of #,
; until a zero double number n2 results. Used between <# and #>.
L9801:	.BYTE	$82,"#",$D3
	.WORD	L97DA	; LFA: previous name field in this vocabulary chain
DIGS:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	DIG
	.WORD	TDUP
	.WORD	ORR
	.WORD	ZEQU
	.WORD	ZBRAN,$FFF6	; Pop flag; if zero branch to $9808 (offset -10 from operand cell)
	.WORD	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: D.R [FORTH].
; Manual stack: ( d n --- )
; Manual: Prints a signed double number d right aligned in a field n
; characters wide.
L9816:
	.BYTE	$83,"D.",$D2
	.WORD	L9801	; LFA: previous name field in this vocabulary chain
DDOTR:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	TOR
	.WORD	SWAP
	.WORD	OVER
	.WORD	DABS
	.WORD	BDIGS
	.WORD	DIGS
	.WORD	SIGN
	.WORD	EDIGS
	.WORD	RFROM
	.WORD	OVER
	.WORD	SUBB
	.WORD	SPACS
	.WORD	TYPE
	.WORD	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: D. [FORTH].
; Manual stack: ( d --- )
; Manual: Prints a signed double number from a 32-bit two's complement value.
; The high-order 16 bits are most accessible on the stack. Conversion is
; performed according to the current BASE. A blank follows. Pronounced "D
; dot." 120
L983A:
	.BYTE	$82,"D",$AE
	.WORD	L9816	; LFA: previous name field in this vocabulary chain
DDOT:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	ZERO
	.WORD	DDOTR
	.WORD	SPACE
	.WORD	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: .R [FORTH].
; Manual stack: ( n1 n2 --- )
; Manual: Prints the number n1 right aligned in a field whose width is n2. No
; following blank is printed.
L9849:
	.BYTE	$82,".",$D2
	.WORD	L983A	; LFA: previous name field in this vocabulary chain
DOTR:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	TOR
	.WORD	STOD
	.WORD	RFROM
	.WORD	DDOTR
	.WORD	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: . [FORTH].
; Manual stack: ( n --- )
; Manual: Prints a number from a signed 16-bit two's complement value,
; converted according to the numeric BASE. Followed by one blank space.
; Pronounced "dot." This is a vectored word.
L985A:
	.BYTE	$81,$AE
	.WORD	L9849	; LFA: previous name field in this vocabulary chain
DOT:
	.WORD	DOVEC	; CFA: vectored word; dispatch through UP+$32+offset
	.BYTE	14	; Vector byte offset 14 from I/O (UP+$32)

PDOT:
	.WORD	DOCOL
	.WORD	STOD
	.WORD	DDOT
	.WORD	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: ? [FORTH].
; Manual stack: ( a --- )
; Manual: Prints the value contained at the address in free format according
; to the current base.
L9869:
	.BYTE	$81,$BF
	.WORD	L985A	; LFA: previous name field in this vocabulary chain
QUES:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	AT
	.WORD	DOT
	.WORD	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: LIST [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n --- )
; Manual: Displays the ASCII text of screen n on the selected output device.
; SCR contains the screen number during and after this process.
L9875:
	.BYTE	$84,"LIS",$D4
	.WORD	L9869	; LFA: previous name field in this vocabulary chain
LIST:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: VLIST [FORTH].
; Manual: Lists the names of the definitions in the context vocabulary. The
; RUN/STOP key will end the listing. Hitting any key will stop the scrolling
; and any key will continue the scrolling.
L98BC:
	.BYTE	$85,"VLIS",$D4
	.WORD	L9875	; LFA: previous name field in this vocabulary chain
VLIST:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	CONT
	.WORD	AT
	.WORD	AT
	.WORD	CR
	.WORD	DUP
	.WORD	IDDOT
	.WORD	TAB
	.WORD	PFA
	.WORD	LFA
	.WORD	QTER
	.WORD	ZBRAN,$D	; Pop flag; if zero branch to $98E9 (offset +13 from operand cell)
	.WORD	KEY
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	3
	.WORD	SUBB
	.WORD	ZBRAN,$C	; Pop flag; if zero branch to $98F3 (offset +12 from operand cell)
	.WORD	AT
	.WORD	DUP
	.WORD	ZEQU
	.WORD	ZBRAN,$FFDD	; Pop flag; if zero branch to $98CE (offset -35 from operand cell)
	.WORD	DROP
	.WORD	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: READS [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1/n2 --- )
; Manual: Used to READ a group of screens from cassette, into screen n1 for a
; count of n2 screens. Cannot be made to read screens from disk, since each
; file must have a unique name.
L98F7:
	.BYTE	$85,"READ",$D3
	.WORD	L98BC	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: WRITES [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1/n2 --- )
; Manual: Screens n1 through n1 + n2 will be written to cassette.
L9913:
	.BYTE	$86,"WRITE",$D3
	.WORD	L98F7	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: LOADS [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: A mass storage word, used to load from cassette a sequence of
; screens into screen butter one, and then a one (1) load is performed. This
; is mainly a hold over from VICFORTH, and was used to minimize the number of
; buffers required to load a program from cassette.
L9930:
	.BYTE	$85,"LOAD",$D3
	.WORD	L9913	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: EM [FORTH].
; IMNOTWOPR: implemented by the serial shell.
; Original C64 manual stack: ( --- a1 )
; Manual: A SYSTEM variable, which holds an address one byte higher than the
; highest user address available to the FORTH dictionary. Changing this
; address will cause both FORTH and the Commodore KERNEL to think the memory
; size has changed. The contents of EM must not be in creased, however, as
; 64FORTH uses all higher memory locations.
L994C:
	.BYTE	$82,"E",$CD
	.WORD	L9930	; LFA: previous name field in this vocabulary chain
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
L9955:
	.BYTE	$84,"THR",$D5
	.WORD	L994C	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: SETNAM [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( a1/n1 --- )
; Manual: A KERNAL system call, used to set the system filename to the string
; at address a1, for length n1 characters.
L996E:
	.BYTE	$86,"SETNA",$CD
	.WORD	$84C	; LFA: previous name field in this vocabulary chain
SETNAM:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: NAME [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- (text) )
; Manual: Accepts A the string of text following, delimited by an up arrow
; "^", into the FN buffer, and performs a system call to the SETNAM KERNEL
; routine.
L998B:
	.BYTE	$84,"NAM",$C5
	.WORD	L9955	; LFA: previous name field in this vocabulary chain
NAME:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: TAB [FORTH].
; Manual stack: ( --- )
; Manual: Tabs to the next tab position on the screen. Used by VLIST and
; several other words requiring output formatting.
L99A0:
	.BYTE	$83,"TA",$C2
	.WORD	L998B	; LFA: previous name field in this vocabulary chain
TAB:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	$A
	.WORD	OUT
	.WORD	AT
	.WORD	OVER
	.WORD	MOD
	.WORD	SUBB
	.WORD	ZERO
	.WORD	MAX
	.WORD	DUP
	.WORD	OUT
	.WORD	AT
	.WORD	PLUS
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	30
	.WORD	GREAT
	.WORD	ZBRAN,$A	; Pop flag; if zero branch to $99D2 (offset +10 from operand cell)
	.WORD	DROP
	.WORD	CR
	.WORD	BRAN,4	; Jump to $99D4 (offset +4 from operand cell)
	.WORD	SPACS
	.WORD	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: TEXT [FORTH].
; Manual stack: ( c1 --- )
; Manual: Accepts text from the input stream delimited by character c1. The
; text accepted is placed at PAD.
L99D6:
	.BYTE	$84,"TEX",$D4
	.WORD	L99A0	; LFA: previous name field in this vocabulary chain
TEXT:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	HERE
	.WORD	CSLL
	.WORD	ONEP
	.WORD	BLANK
	.WORD	WORD
	.WORD	HERE
	.WORD	PAD
	.WORD	CSLL
	.WORD	ONEP
	.WORD	CMOVE
	.WORD	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: LINE [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- a1 )
; Manual: Returns address all of line n1 in current edit screen as specified
; by variable SCR.
L99F5:
	.BYTE	$84,"LIN",$C5
	.WORD	L99D6	; LFA: previous name field in this vocabulary chain
LINE:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: 2DUP [FORTH].
; Manual stack: ( n1/n2 --- n1/n2/n1/n2 )
; Manual: Duplicates the top two single length elements on the data stack.
; Pronounced "two dup."
L9A1D:
	.BYTE	$84,"2DU",$D0
	.WORD	L99F5	; LFA: previous name field in this vocabulary chain
TDUP:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	OVER
	.WORD	OVER
	.WORD	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: 2SWAP [FORTH].
; Manual stack: ( n1/n2/n3/n4 --- n3/n4/n1/n2 )
; Manual: Exchanges the order of the top two pairs of elements on the data
; stack.
L9A2C:
	.BYTE	$85,"2SWA",$D0
	.WORD	L9A1D	; LFA: previous name field in this vocabulary chain
TSWAP:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	ROT
	.WORD	TOR
	.WORD	ROT
	.WORD	RFROM
	.WORD	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: U. [FORTH].
; Manual stack: ( u1 --- )
; Manual: Displays the unsigned number in the current BASE on the screen,
; with one trailing blank following the free formatted number.
L9A40:
	.BYTE	$82,"U",$AE
	.WORD	L9A2C	; LFA: previous name field in this vocabulary chain
UDOT:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	ZERO
	.WORD	DDOT
	.WORD	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: H. [FORTH].
; Manual stack: ( n1 --- )
; Manual: Prints the value n1 to the current output device in the HEXADECIMAL
; number base and in an unsigned format.
L9A4D:
	.BYTE	$82,"H",$AE
	.WORD	L9A40	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	BASE
	.WORD	AT
	.WORD	SWAP
	.WORD	HEX
	.WORD	UDOT
	.WORD	BASE
	.WORD	STORE
	.WORD	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: DUMP [FORTH].
; Manual stack: ( a1/n1 --- )
; Manual: The contents of memory starting at address a1 for a length of n1
; bytes is displayed on the screen, in the current number base, with 8 bytes
; per line, preceeded by the address of the first byte in the line.
L9A64:
	.BYTE	$84,"DUM",$D0
	.WORD	L9A4D	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	OVER
	.WORD	PLUS
	.WORD	SWAP
	.WORD	CR
	.WORD	PDO
	.WORD	I
	.WORD	ZERO
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	5
	.WORD	DDOTR
	.WORD	I
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	8
	.WORD	PLUS
	.WORD	I
	.WORD	PDO
	.WORD	I
	.WORD	CAT
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	4
	.WORD	DOTR
	.WORD	PLOOP,$FFF5	; Increment loop index; if continuing branch to $9A8B (offset -11 from operand cell)
	.WORD	CR
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	8
	.WORD	PPLOO,$FFD8	; Add stack increment; if continuing branch to $9A77 (offset -40 from operand cell)
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; SCREEN / LINE EDITOR
; ---------------------------------------------------------------------------
; Dictionary: #LOCATE [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- n1/n2 )
; Manual: An editor primitive which returns the cursor line as n1 and the
; character position on the line as n2.
L9AA3:
	.BYTE	$87,"#LOCAT",$C5
	.WORD	$84C	; LFA: previous name field in this vocabulary chain
NLOCAT:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: BMOV [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( a1 --- )
; Manual: An editor primitive, (that moves the contents of PAD for C/L
; characters to address a1) if PAD contains text other than a null in the
; first character position (pad+1), otherwise, nothing is done.
L9ABB:
	.BYTE	$84,"BMO",$D6
	.WORD	L9AA3	; LFA: previous name field in this vocabulary chain
BMOV:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: PADF [EDITOR].
; Manual stack: ( --- a1 )
; Manual: An editor buffer, 65 characters long used to hold the strings of
; text searched for the find buffer.
L9ADE:
	.BYTE	$84,"PAD",$C6
	.WORD	L9ABB	; LFA: previous name field in this vocabulary chain
PADF:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	PAD
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	80
	.WORD	PLUS
	.WORD	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: PADI [EDITOR].
; Manual stack: (--- a1 )
; Manual: An editor buffer 65 characters long used to hold the strings of
; text inserted: the insert buffer.
L9AF0:
	.BYTE	$84,"PAD",$C9
	.WORD	L9ADE	; LFA: previous name field in this vocabulary chain
PADI:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	PADF
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	80
	.WORD	PLUS
	.WORD	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: !CUR [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Moves edit cursor to character position 0 in current edit screen if
; n1 is in the range 0 to B/BUF-1. !CUR will only change the current cursor
; position if 0 is within the valid range. Causes the current edit window
; around the cursor to be viewed in the upper 16 lines of the display.
L9B02:
	.BYTE	$84,"!CU",$D2
	.WORD	L9AF0	; LFA: previous name field in this vocabulary chain
STOCUR:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: L# [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- n1 )
; Manual: An editor primitive, which returns the fine number of the line
; which currently contains the cursor.
L9B2D:
	.BYTE	$82,"L",$A3
	.WORD	L9B02	; LFA: previous name field in this vocabulary chain
LNUM:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: #LEAD [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- a1/n1 )
; Manual: An editor primitive, which returns the address of the cursor line
; as a1, and the number of characters before the cursor on the line as n1.
L9B3C:
	.BYTE	$85,"#LEA",$C4
	.WORD	L9B2D	; LFA: previous name field in this vocabulary chain
NLEAD:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: #LAG [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- a1/n1 )
; Manual: An editor primitive, which returns the address of the cursor as a1,
; and the number of characters remaining on the following the cursor as n1.
L9B4E:
	.BYTE	$84,"#LA",$C7
	.WORD	L9B3C	; LFA: previous name field in this vocabulary chain
NLAG:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: -MOVE [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( a1/n1 --- )
; Manual: Moves c/l characters of text from address a1 to line n1 of current
; edit screen. The screen is updated.
L9B67:
	.BYTE	$85,"-MOV",$C5
	.WORD	L9B4E	; LFA: previous name field in this vocabulary chain
DMOVE:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: H [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: An editor word, which causes a copy of the line currently
; containing the cursor to be moved to the insert buffer PADI. The text can
; later be reinserted with "U", or "I" or "P".
L9B7B:
	.BYTE	$81,$C8
	.WORD	L9B67	; LFA: previous name field in this vocabulary chain
HH:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: K [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: An editor word, which erases or "KILLS" the current cursor line.
; The line is filled with blanks, but no text compression occurs.
L9B95:
	.BYTE	$81,$CB
	.WORD	L9B7B	; LFA: previous name field in this vocabulary chain
KK:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: S [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: An editor word, causes all lines from the current cursor line down
; to be SPREAD down, by one line. Line 15 will be lost, and the current
; cursor line will become blank.
L9BA7:
	.BYTE	$81,$D3
	.WORD	L9B95	; LFA: previous name field in this vocabulary chain
SS:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: X [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: An editor word which deletes the current cursor line, placing it in
; PADI--the insert buffer. All lower lines are moved up to fill the space.
; The text may be put back into the edit screen, with U <RETURN>, after
; moving the cursor to the desired line.
L9BCC:
	.BYTE	$81,$D8
	.WORD	L9BA7	; LFA: previous name field in this vocabulary chain
XX:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: C [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: An editor primitive, used to move the cursor a RELATIVE amount
; within the current edit screen. The signed value n1 is added to the current
; cursor location, and If the value is within the current screen, the cursor
; location is updated to the new value. Otherwise the cursor location is
; unchanged. 115
L9C07:
	.BYTE	$81,$C3
	.WORD	L9BCC	; LFA: previous name field in this vocabulary chain
CC:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: T [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: An editor word, moves the cursor to the beginning of line n11 on
; the current edit screen. N1 is in the range 0 to 15.
L9C17:
	.BYTE	$81,$D4
	.WORD	L9C07	; LFA: previous name field in this vocabulary chain
TT:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: GTEXT [EDITOR].
; Manual stack: ( --- )
; Manual: An editor primitive. accepts text from the input stream, until a
; delimiting "^" is encountered, or the (RETURN) key is pressed. The text is
; placed at address a1, for a length of 65 characters.
L9C25:
	.BYTE	$85,"GTEX",$D4
	.WORD	L9C17	; LFA: previous name field in this vocabulary chain
GTEXT:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	CLIT	; Push following inline byte, zero-extended
	.BYTE	"^"
	.WORD	TEXT
	.WORD	BMOV
	.WORD	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: P [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Implementation: Editor: parse the following text into PADI, then replace
; the current line using L9C46.
L9C38:
	.BYTE	$81,$D0
	.WORD	L9C25	; LFA: previous name field in this vocabulary chain
PP:
L9C46:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: U [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- (text) )
; Manual: An editor word which places the (text) following U under the
; current cursor line. (text) is optional.
L9C54:
	.BYTE	$81,$D5
	.WORD	L9C38	; LFA: previous name field in this vocabulary chain
UU:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: TOP [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual: Sends the cursor to the top left corner of the screen--the home
; position.
L9C68:
	.BYTE	$83,"TO",$D0
	.WORD	L9C54	; LFA: previous name field in this vocabulary chain
TOP:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: COPY [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1/n2 --- )
; Manual: Copies screen n1 to screen n2, thereby creating a duplicate screen.
L9C76:
	.BYTE	$84,"COP",$D9
	.WORD	L9C68	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: MATCH [EDITOR].
; Implementation: Search candidate addresses with (MATCH), retaining the
; pattern address/length across the loop. Return a found flag and a
; cursor-advance count; 1LINE uses that count to update R#.
L9C93:
	.BYTE	$85,"MATC",$C8
	.WORD	L9C76	; LFA: previous name field in this vocabulary chain
MATCH:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	TOR
	.WORD	TOR
	.WORD	TDUP
	.WORD	RFROM
	.WORD	RFROM
	.WORD	TSWAP
	.WORD	OVER
	.WORD	PLUS
	.WORD	SWAP
	.WORD	PDO
	.WORD	TDUP
	.WORD	I
	.WORD	SWAP
	.WORD	PMATCH
	.WORD	ZBRAN,$1A	; Pop flag; if zero branch to $9CD5 (offset +26 from operand cell)
	.WORD	TOR
	.WORD	TDROP
	.WORD	RFROM
	.WORD	SUBB
	.WORD	I
	.WORD	SWAP
	.WORD	SUBB
	.WORD	ZERO
	.WORD	SWAP
	.WORD	ZERO
	.WORD	ZERO
	.WORD	LEAVE
	.WORD	PLOOP,$FFDA	; Increment loop index; if continuing branch to $9CB1 (offset -38 from operand cell)
	.WORD	TDROP
	.WORD	SWAP
	.WORD	ZEQU
	.WORD	SWAP
	.WORD	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: 1LINE [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Implementation: ( -- found ) Search from the cursor to the end of its line
; for PADF text, update R# by the returned advance, and leave the match flag.
L9CE3:
	.BYTE	$85,"1LIN",$C5
	.WORD	L9C93	; LFA: previous name field in this vocabulary chain
ONELIN:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: (F) [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: This is a low level editor primitive, which searches for the next
; occurence of the text in the PADF buffer. Not normally used by the user,
; but could be useful if the editor was being expanded with additional
; commands.
L9CFB:
	.BYTE	$83,"(F",$A9
	.WORD	L9CE3	; LFA: previous name field in this vocabulary chain
PFF:
L9D19:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: DEL [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: An editor primitive, which deletes n1 characters before the cursor;
; clips at the beginning of the screen, to prevent deleting off the screen.
; Text to the right of the cursor on the current line will be moved left to
; fill the space of the deleted characters.
L9D36:
	.BYTE	$83,"DE",$CC
	.WORD	L9CFB	; LFA: previous name field in this vocabulary chain
DEL:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: F [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- (text)
; Manual: An editor word which finds the first occurence of (text) following
; an "F" command. Starts at the current cursor location. (text) is optional,
; and "F (return)" will find the next occurence of the last text searched
; for.
L9D9A:
	.BYTE	$81,$C6
	.WORD	L9D36	; LFA: previous name field in this vocabulary chain
FF:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: E [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: An editor word, used after an "F" command, to ERASE the text just
; found. Deletes characters for the length of the text in the find buffer.
L9DA8:
	.BYTE	$81,$C5
	.WORD	L9D9A	; LFA: previous name field in this vocabulary chain
EE:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: D [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- (text) )
; Manual: Deletes the first occurence of (text) following the D command and
; then searches from the edit cursor until the end of the screen. (text) is
; optional, and if omitted, will cause D to delete the same string as used
; previously.
L9DB6:
	.BYTE	$81,$C4
	.WORD	L9DA8	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: TILL [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Implementation: Editor: read a search string, locate it on the current
; line, and delete the span from the old cursor to the resulting cursor.
; L9D19 handles a failed search.
L9DC2:
	.BYTE	$84,"TIL",$CC
	.WORD	L9DB6	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: (I) [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: A low level editor primitive, which inserts the character string
; held in PADI, into the next text screen at the current location specified
; by the contents of R#. Potentially useful for future expansion of the
; editor.
L9DE5:
	.BYTE	$83,"(I",$A9
	.WORD	L9DC2	; LFA: previous name field in this vocabulary chain
PII:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: I [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- (text) )
; Manual: An editor word, causes (text) to be inserted at the current
; location of the cursor, with all text following the cursor being moved over
; to make room. Text on the cursor line too long for the line after the
; insert will be LOST. (text) is optional, and use of "I" without following
; text, causes the current contents of PADI the insert buffer to be inserted.
L9E11:
	.BYTE	$81,$C9
	.WORD	L9DE5	; LFA: previous name field in this vocabulary chain
II:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: R [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- (text) )
; Manual: An editor command, replaces the string just found with the "F"
; command with the (text) following "R" command. (text) is optional, and if
; omitted, will cause a replace with the last text used in the replace
; command.
L9E1F:
	.BYTE	$81,$D2
	.WORD	L9E11	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: N [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- a1 ) (assembling)
; Manual: Used in a code-definition in the form: N1 - STA, or n2 = )Y ADC, A
; constant which leaves the address of a 9 byte workspace in z-page. Within a
; single code definition, free use may be made over the range N-1 through
; N-7.
L9E2B:
	.BYTE	$81,$CE
	.WORD	L9E1F	; LFA: previous name field in this vocabulary chain
NN:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: B [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: An editor operation, which causes the edit to be moved to the
; previous screen. Pronounced "back." 112
L9E39:
	.BYTE	$81,$C2
	.WORD	L9E2B	; LFA: previous name field in this vocabulary chain
BB:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: +SCR [EDITOR].
; Manual stack: ( n1 --- )
; Manual: Adds the signed value n1 to the current editor screen number, and
; clips the result to within the currently specified valid screen range, 1 to
; BMAX.
L9E49:
	.BYTE	$84,"+SC",$D2
	.WORD	L9E39	; LFA: previous name field in this vocabulary chain
PSCR:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	SCR
	.WORD	AT
	.WORD	PLUS
	.WORD	ONE
	.WORD	MAX
	.WORD	BMAX
	.WORD	AT
	.WORD	MIN
	.WORD	SCR
	.WORD	STORE
	.WORD	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: WIPE [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: An editor word that causes the current editor screen to be cleared
; to blanks.
L9E68:
	.BYTE	$84,"WIP",$C5
	.WORD	L9E49	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: M [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1/n2 --- )
; Manual: An editor line MOVE word used to move the line currently containing
; the cursor to screen n1, under line n2.
L9E89:
	.BYTE	$81,$CD
	.WORD	L9E68	; LFA: previous name field in this vocabulary chain
L9EBF:
L9F24:
L9F35:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: V [EDITOR].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: Causes a VIEW of the current edit screen, around the currently
; specified cursor location. 149
L9F53:
	.BYTE	$81,$D6
	.WORD	L9E89	; LFA: previous name field in this vocabulary chain
VV:
L9FF3:
LA002:
LA048:
LA051:
LA05B:
LA065:
LA06D:
LA077:
LA07F:
LA089:
LA091:
LA099:
LA0A1:
LA0AB:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: EDIT [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Enters the split screen editor, on screen n1. The EDITOR is
; selected, and the editor capture table is enabled. See the EDITOR
; documentation, for further information on editor commands.
LA0B5:
	.BYTE	$84,"EDI",$D4
	.WORD	L9A64	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: ASCII [FORTH]; immediate (executes during compilation).
; Manual stack: ( --- t n1 )
; Manual: Accepts the word following ASCII, and returns the ASCII value of
; the first character of the word on the data stack.
LA0E3:
	.BYTE	$C5,"ASCI",$C9
	.WORD	LA0B5	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	BL
	.WORD	WORD
	.WORD	HERE
	.WORD	ONEP
	.WORD	CAT
	.WORD	LITER
	.WORD	SEMIS	; Return to caller thread

; ---------------------------------------------------------------------------
; C64 MACHINE-CODE AND FILE / SERIAL I/O BRIDGES
; ---------------------------------------------------------------------------

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
LA0FB:
	.BYTE	$83,"SY",$D3
	.WORD	L996E	; LFA: previous name field in this vocabulary chain
; MACHINE-CODE BRIDGE. Stack input is (carry A X Y address), with address on
; top. Only low bytes supply registers; the optional carry cell is inspected
; but retained. Save Forth X, call through LA135, then replace low bytes of
; the A/X/Y cells with returned registers, save processor status in N, and
; drop address. High bytes of register cells are not cleared.
SYS:
	.WORD	*+2	; CFA: native 6502 code starts immediately after this cell
    REQUIRE_CELLS 5
	STX	XSAVE
	LDA	0,X
	STA	NXTMP
	LDA	1,X
	STA	NXTMP+1
	LDY	2,X
	LDA	4,X
	STA	N
	LDA	8,X
	BNE	LA11A
	CLC
	BCC	LA11B
LA11A:
	SEC
LA11B:
	LDA	6,X
	LDX	N
	JSR	LA135
	PHP
	STX	N
	LDX	XSAVE
	STA	6,X
	LDA	N
	STA	4,X
	STY	2,X
	PLA
	STA	N
	JMP	POP

; Indirect JSR trampoline: SYS uses JSR here, then JMP (NXTMP) lets the
; target RTS return directly to SYS.
LA135:
	JMP	(NXTMP)

; ----------------------------------------------------------------------------
; Dictionary: READ [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Used to read a screen from cassette, into screen number n1. Will
; read screen from cassette with names, by specifying a name with the NAME
; command prior to READ. The variables D# and F# are used to determine which
; device and file number are used to read from. Therefore, it is possible to
; read files from disk.
LA138:
	.BYTE	$84,"REA",$C4
	.WORD	LA0E3	; LFA: previous name field in this vocabulary chain
READ:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: FSET [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: A low level file control word which performs a SETLFS system call
; with the current values of D# and F#. Used by READ and WRITE. 129
LA14B:
	.BYTE	$84,"FSE",$D4
	.WORD	LA0FB	; LFA: previous name field in this vocabulary chain
FSET:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: SETLFS [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1/n2/n3 --- )
; Manual: A KERNAL system call, sets the logical file with file number n1,
; device number n2, and secondary command n3 into the KERNEL operating
; system.
LA162:
	.BYTE	$86,"SETLF",$D3
	.WORD	LA14B	; LFA: previous name field in this vocabulary chain
SETLFS:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: 3DROP [FORTH].
; Manual stack: ( n1/n2/n3 --- )
; Manual: A code-saving word, which drops three arguments from the data
; stack. Used by several system call words.
LA177:
	.BYTE	$85,"3DRO",$D0
	.WORD	LA138	; LFA: previous name field in this vocabulary chain
THDROP:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	TDROP
	.WORD	DROP
	.WORD	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: OPEN [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: A KERNEL system call, which opens a channel as previously specified
; with the SETNAM and SETLFS commands.
LA187:
	.BYTE	$84,"OPE",$CE
	.WORD	LA162	; LFA: previous name field in this vocabulary chain
OPEN:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: SLOAD [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( a1 --- )
; Manual: A KERNEL system call, which loads the file specified by currently
; selected file name from the currently selected device into memory starting
; at address a1. This word is used after performing a NAME and SETLFS
; operation.
LA19A:
	.BYTE	$85,"SLOA",$C4
	.WORD	LA187	; LFA: previous name field in this vocabulary chain
SLOAD:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: SAVE [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( a1/n1 --- )
; Manual: Saves the data or program starting at address a1, for a length of
; n1 bytes, to the currently open mass storage device.
LA1B8:
	.BYTE	$84,"SAV",$C5
	.WORD	LA19A	; LFA: previous name field in this vocabulary chain
SAVE:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: WRITE [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Writes screen n1 to the current device as specified by D# and F#.
; The written screen will be sent to cassette by default.
LA1DF:
	.BYTE	$85,"WRIT",$C5
	.WORD	LA177	; LFA: previous name field in this vocabulary chain
WRITE:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: CHKOUT [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: A KERNEL system call, which redirects character output to the
; channel specified as n1. The channel n1 must already be opened.
LA1F3:
	.BYTE	$86,"CHKOU",$D4
	.WORD	LA1B8	; LFA: previous name field in this vocabulary chain
CHKOUT:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: CLALL [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: A SYSTEM primitive, used to clear all channels, in the Commodore
; KERNEL to their default values. See the Commodore Programmers Reference
; Manual.
LA20E:
	.BYTE	$85,"CLAL",$CC
	.WORD	LA1F3	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

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
LA222:
	.BYTE	$85,"CHRI",$CE
	.WORD	LA20E	; LFA: previous name field in this vocabulary chain
CHRIN:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: BGROUND [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Selects background color for the screen, using the standard values
; for Commodore colors in the range 0 to 15.
LA232:
	.BYTE	$87,"BGROUN",$C4
	.WORD	LA1DF	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: BORDER [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Selects the screen BORDER color. N1 is a value between 0 and 15,
; for the colors as shown on page 139 of the Commodore 64 Users Guide.
LA246:
	.BYTE	$86,"BORDE",$D2
	.WORD	LA232	; LFA: previous name field in this vocabulary chain
BORDR:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: UPORT [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- a1 )
; Manual: Returns the address of the user port In the Commodore 64 computer.
; Address a1 is the data port address.
LA259:
	.BYTE	$85,"UPOR",$D4
	.WORD	LA246	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: DISK [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: This word selects the disk device for further mass storage
; operations by setting variable D# to the device specified by variable DR#,
; which is the actual drive number plus 8 (eight). This word is performed
; automatically by "FILE" operations. 121
LA265:
	.BYTE	$84,"DIS",$CB
	.WORD	LA259	; LFA: previous name field in this vocabulary chain
DISK:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: CASSETTE [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: Selects the cassette for all further mass storage operations. This
; is the default mode, so it is not normally necessary to switch to CASSETTE.
; When a disk file has been opened and then closed, operation is
; automatically switched back to cassette.
LA288:
	.BYTE	$88,"CASSETT",$C5
	.WORD	LA265	; LFA: previous name field in this vocabulary chain
CASSET:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: TALK [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: A KERNEL system call, which commands a device in the range of 0 to
; 31 to TALK on the serial bus. 146
LA2AB:
	.BYTE	$84,"TAL",$CB
	.WORD	LA222	; LFA: previous name field in this vocabulary chain
TALK:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: TKSA [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: A KERNEL system call, which sends byte value n1 in the range 0 to
; 31 as a secondary address command on the serial bus. This command is
; normally used after a TALK command to a device.
LA2C0:
	.BYTE	$84,"TKS",$C1
	.WORD	LA2AB	; LFA: previous name field in this vocabulary chain
TKSA:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: 0.0 [SYSTEM].
; Manual stack: ( --- d1 )
; Manual: A space saving constant, which returns the double length (32-bit)
; value zero, used in several system calls.
LA2D5:
	.BYTE	$83,"0.",$B0
	.WORD	LA2C0	; LFA: previous name field in this vocabulary chain
DZERO:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	ZERO
	.WORD	ZERO
	.WORD	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: UNTLK [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Implementation: ( -- ) Call KERNAL UNTLK to end the serial TALK condition;
; discard returned register cells.
LA2E3:
	.BYTE	$85,"UNTL",$CB
	.WORD	LA2D5	; LFA: previous name field in this vocabulary chain
UNTLK:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: UNLSN [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: A KERNEL system call, which tells all devices on the serial bus
; which were previously listening, to stop listening. Pronounced "unlisten."
LA2FB:
	.BYTE	$85,"UNLS",$CE
	.WORD	LA2E3	; LFA: previous name field in this vocabulary chain
UNLSN:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: ACPTR [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Implementation: ( -- byte ) Call KERNAL ACPTR and keep the returned A cell,
; dropping X/Y.
LA313:
	.BYTE	$85,"ACPT",$D2
	.WORD	LA2FB	; LFA: previous name field in this vocabulary chain
ACPTR:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: LISTEN [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Sends a command to cause device address n1 to listen for data on
; the serial bus.
LA32B:
	.BYTE	$86,"LISTE",$CE
	.WORD	LA313	; LFA: previous name field in this vocabulary chain
LISTEN:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: CIOUT [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: A KERNEL system call, which sends a character n1 out of the serial
; bus. 116
LA342:
	.BYTE	$85,"CIOU",$D4
	.WORD	LA32B	; LFA: previous name field in this vocabulary chain
CIOUT:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: SECOND [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: A KERNEL system call, which sends the secondary address on the
; serial bus, normally sent after the LISTEN command. See also SLSN and
; LISTEN.
LA358:
	.BYTE	$86,"SECON",$C4
	.WORD	LA342	; LFA: previous name field in this vocabulary chain
SECOND:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: STYPE [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( a1/n1 --- )
; Manual: Sends n1 characters from address a1, out the serial bus. STYPE must
; be used after telling a device to listen. This is a low level primitive
; used by the system.
LA36F:
	.BYTE	$85,"STYP",$C5
	.WORD	LA358	; LFA: previous name field in this vocabulary chain
STYPE:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: DTLK [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Sends a secondary address n l after telling the disk to talk.
; Pronounced "disk talk." 123
LA38D:
	.BYTE	$84,"DTL",$CB
	.WORD	LA36F	; LFA: previous name field in this vocabulary chain
DTLK:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: DLSN [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Sends a secondary address to the disk, after telling the disk to
; LISTEN. Pronounced "disk listen."
LA3A6:
	.BYTE	$84,"DLS",$CE
	.WORD	LA38D	; LFA: previous name field in this vocabulary chain
DLSN:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: ?DERR [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: This word is very similar to ?D, but only prints a message to the
; terminal if there was a disk error. If no error has occurred, then
; operation continues after ?DERR. If an error condition was detected,
; execution is aborted.
LA3BF:
	.BYTE	$85,"?DER",$D2
	.WORD	LA288	; LFA: previous name field in this vocabulary chain
QDERR:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: ?D [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: This is a short word used to determine status of the disk, and to
; clear any error condition that might occur while disk operations are
; performed.
LA41E:
	.BYTE	$82,"?",$C4
	.WORD	LA3BF	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: --> [FORTH]; immediate (executes during compilation).
; Manual: Continues interpretation with the next disk screen. Pronounced
; "next-screen." 106
LA42F:
	.BYTE	$C3,"--",$BE
	.WORD	LA41E	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	ONE
	.WORD	BLK
	.WORD	PSTOR
	.WORD	ZERO
	.WORD	IN
	.WORD	STORE
	.WORD	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: <^> [FORTH].
; Manual stack: ( --- a1/n1 )
; Manual: A low level primitive compiled in-line when a string is built
; in-line in a colon-definition. This word returns the address of the string
; and the count of its length on the data stack. Not used from the keyboard.
LA445:
	.BYTE	$83,"<^",$BE
	.WORD	LA42F	; LFA: previous name field in this vocabulary chain
ALIT:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	R
	.WORD	DUP
	.WORD	CAT
	.WORD	ONEP
	.WORD	RFROM
	.WORD	PLUS
	.WORD	TOR
	.WORD	COUNT
	.WORD	SEMIS	; Return to caller thread

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
LA45F:
	.BYTE	$C1,$DE
	.WORD	LA445	; LFA: previous name field in this vocabulary chain
UARROW:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	STATE
	.WORD	AT
	.WORD	ZBRAN,$18	; Pop flag; if zero branch to $A483 (offset +24 from operand cell)
	.WORD	COMP
	.WORD	ALIT	; Inline CFA operand consumed by COMPILE
	.WORD	LIT,$5E		; '^'
	.WORD	WORD
	.WORD	HERE
	.WORD	CAT
	.WORD	ONEP
	.WORD	ALLOT
	.WORD	BRAN,$1A	; Jump to $A49B (offset +26 from operand cell)
	.WORD	LIT,$5E		; '^'
	.WORD	WORD
	.WORD	HERE
	.WORD	DUP
	.WORD	CAT
	.WORD	ONEP
	.WORD	PAD
	.WORD	SWAP
	.WORD	CMOVE
	.WORD	PAD
	.WORD	COUNT
	.WORD	SEMIS	; Return to caller thread

; ----------------------------------------------------------------------------
; Dictionary: DRIVE [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Selects drive n1 as the currently active disk drive, by setting
; user variable DR# to the drive number plus 8. See also DRIVE? and DR#.
LA49D:
	.BYTE	$85,"DRIV",$C5
	.WORD	LA45F	; LFA: previous name field in this vocabulary chain
DRIVE:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: DRIVE? [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- n1 )
; Manual: Returns the drive number of the currently active disk drive;
; defaults to device 8 drive 0. See also DRIVE and DR#.
LA4B3:
	.BYTE	$86,"DRIVE",$BF
	.WORD	LA49D	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: DTYPE [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1/a1/n2 --- )
; Manual: Sends the character string at address a1, for length n2 to channel
; n1 in the serial bus. Pronounced "disk type."
LA4CA:
	.BYTE	$85,"DTYP",$C5
	.WORD	LA3A6	; LFA: previous name field in this vocabulary chain
DTYPE:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: /CMD [FORTH]; immediate (executes during compilation).
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- t )
; Manual: Sends the text string 't' to channel n1 on the serial bus. This is
; a lower level word than CMD, which always sends a command string to the
; disk drive.
LA4E4:
	.BYTE	$C4,"/CM",$C4
	.WORD	LA4B3	; LFA: previous name field in this vocabulary chain
SCMD:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

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
LA503:
	.BYTE	$C3,"CM",$C4
	.WORD	LA4E4	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: (FILE) [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- t )
; Manual: This is a low level word used by FILE, which opens the file
; specified by text 't'. (FILE) does not empty the screens out of memory
; before opening the new file. This word is used mostly when copying screens
; from cassette to disk, or when copying screens from one disk file to
; another.
LA515:
	.BYTE	$86,"(FILE",$A9
	.WORD	LA503	; LFA: previous name field in this vocabulary chain
PFILE:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: ^FILE [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( a1/n1 --- )
; Manual: This word opens the file name string at address a1, for character
; length n1, after first closing any file that is currently open. The text
; string should not be placed at HERE, because HERE is used for other
; processing. The variable FN is recommended as the optimum location for file
; name storage.
LA52C:
	.BYTE	$85,"^FIL",$C5
	.WORD	LA515	; LFA: previous name field in this vocabulary chain
UFILE:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: (^FILE) [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( a1/n1 --- )
; Manual: Similar to (FILE), but requires an address a1 of the text string
; for the file to open, and n1 the length of the name. The file is opened,
; but memory Is not cleared before opening the file. See also ^FILE (FILE)
; FILE. 104
LA53C:
	.BYTE	$87,"(^FILE",$A9
	.WORD	LA52C	; LFA: previous name field in this vocabulary chain
PUFIL:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

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
LA577:
	.BYTE	$84,"FIL",$C5
	.WORD	LA53C	; LFA: previous name field in this vocabulary chain
FILE:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: (FCLOSE) [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: This is a low level word used by FCLOSE, which closes the currently
; open disk file without emptying the memory buffer contents. Useful mostly
; for transferring screens from cassette to disk, and when copying screens
; from one file to another with the utility FCOPY.
LA586:
	.BYTE	$88,"(FCLOSE",$A9
	.WORD	LA577	; LFA: previous name field in this vocabulary chain
PFCLOS:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: FCLOSE [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: Closes the current disk file and clears all screen buffers to
; blanks. If you need to close a file without clearing the screen buffers,
; use (FCLOSE). 127
LA5B1:
	.BYTE	$86,"FCLOS",$C5
	.WORD	LA586	; LFA: previous name field in this vocabulary chain
FCLOSE:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: POS [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Sets the position of the relative fife pointer to record n1.
; 64FORTH uses 129 byte records.
LA5C4:
	.BYTE	$83,"PO",$D3
	.WORD	LA4CA	; LFA: previous name field in this vocabulary chain
POS:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: SLSN [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: A system primitive, which commands the disk drive to listen with a
; secondary address of n1. Pronounced "secondary listen."
LA5F2:
	.BYTE	$84,"SLS",$CE
	.WORD	LA5C4	; LFA: previous name field in this vocabulary chain
SLSN:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: RECWRITE [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( a1/n1 --- )
; Manual: Writes a record to the currently open disk file, from address a1,
; for length n1 bytes, and terminates the write with a carriage return (13
; decimal). Caution is recommended in the use of this word; normally a POS is
; performed before a RECWRITE. n1 is always 128 in 64FORTH.
LA60B:
	.BYTE	$88,"RECWRIT",$C5
	.WORD	LA5F2	; LFA: previous name field in this vocabulary chain
RECWRT:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: RECREAD [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( a1 --- a2 )
; Manual: Reads a record from the currently open disk file, into address a1,
; and returns address a2, which is address a1 plus length of the normal read.
; Caution is recommended in the use of this word. Normally a POS is performed
; before a RECREAD.
LA62A:
	.BYTE	$87,"RECREA",$C4
	.WORD	LA60B	; LFA: previous name field in this vocabulary chain
RECREA:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: BLKWRITE [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( a1/n1 --- )
; Manual: This is a disk block primitive, which writes block n1 to disk from
; address a1, to the currently open RELATIVE disk file. A disk error will be
; reported the first time a write is performed to a previously non-existent
; screen. However, this error should be ignored if it is a non-existent
; record error.
LA666:
	.BYTE	$88,"BLKWRIT",$C5
	.WORD	LA62A	; LFA: previous name field in this vocabulary chain
BLKWRT:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: BLKREAD [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( a1/n1 --- )
; Manual: The disk storage primitive which reads block n1 into address a1
; from the currently open RELATIVE file. A disk error will be reported when
; reading or writing the first time to a newly created screen in a disk file.
; This error should be ignored, as it is a peculiarity of the Commodore Disk
; Operating System.
LA69F:
	.BYTE	$87,"BLKREA",$C4
	.WORD	LA666	; LFA: previous name field in this vocabulary chain
BLKRD:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: R/W [SYSTEM].
; Manual stack: ( a blk f --- )
; Manual: The fig-FORTH standard disk read-write linkage. A (address)
; specifies the source or destination block buffer; blk is the sequential
; number of the referenced block; and f 139 is a flag for f=0 write and f=1
; read. R/W determines the location on mass storage, performs the read-write
; and performs any error checking. This is a vectored word.
LA6D5:
	.BYTE	$83,"R/",$D7
	.WORD	LA69F	; LFA: previous name field in this vocabulary chain
RSLW:
	.WORD	DOVEC	; CFA: vectored word; dispatch through UP+$32+offset
	.BYTE	22	; Vector byte offset 22 from I/O (UP+$32)

PRSLW:
	.WORD	NO_C64	; C64 storage backend unavailable

; ---------------------------------------------------------------------------
; Dictionary: UPDATE [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual: Marks the most recently referenced block as altered. The block will
; subsequently be transferred automatically to disk should its buffer be
; required for storage of a different block.
LA702:
	.BYTE	$86,"UPDAT",$C5
	.WORD	LA5B1	; LFA: previous name field in this vocabulary chain
UPDATE:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: EMPTY-BUFFERS [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual: Mark all block-buffers as empty, not necessarily affecting the
; contents. Updated blocks are not written to the disk. This is also an
; initialization procedure before first use of the disk.
LA71F:
	.BYTE	$8D,"EMPTY-BUFFER",$D3
	.WORD	LA702	; LFA: previous name field in this vocabulary chain
MTBUF:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

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
LA73D:
	.BYTE	$84,">RA",$CD
	.WORD	LA6D5	; LFA: previous name field in this vocabulary chain
; Banking entry: write $7F to CIA1IC to disable its IRQ sources, then $34 to
; the 6510 port via ONE C!. This exposes RAM under ROM/I/O. The copied
; interpreter in underlying RAM makes continued execution possible.
TORAM:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: RAM> [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: Selects the KERNEL and I/O back into the system, pronounced RAM
; FROM. See also >RAM.
LA75A:
	.BYTE	$84,"RAM",$BE
	.WORD	LA73D	; LFA: previous name field in this vocabulary chain
; Banking exit: write $37 to the 6510 port to restore cartridge/KERNAL/I/O
; mapping, then enable CIA 1 timer A IRQs with $81. This restores fixed
; defaults, not a previously saved bank/IRQ mask. LA765 is the documented
; soft-load patch byte.
FRAM:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

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
LA777:
	.BYTE	$84,">BU",$C6
	.WORD	LA75A	; LFA: previous name field in this vocabulary chain
TOBUF:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: BUF> [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( a1/n1 --- )
; Manual: Moves the data for screen n1 from the virtual screen buffer to
; address a1, used by GBLOCK to perform SCREEN DEBLOCKING.
LA78C:
	.BYTE	$84,"BUF",$BE
	.WORD	LA777	; LFA: previous name field in this vocabulary chain
FBUF:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: BUFADD [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- a1 )
; Manual: This word calculates the address of the buffer which should hold
; the screen specified as n1, and returns the buffer address as a1.
LA7A3:
	.BYTE	$86,"BUFAD",$C4
	.WORD	LA78C	; LFA: previous name field in this vocabulary chain
; Backing slot address = $C000 + 1024*((max((block & $7FFF)-1,0)) & 15).
; Strip the dirty flag before indexing. Sixteen slots wrap cyclically; PTRADD
; indexes the parallel 16-cell tag table.
BUFAD:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: PTRADD [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- a1 )
; Manual: A system primitive, which accepts the value n1, a screen and
; returns the address a1 which is the address inside of the BLKTBL array
; which specifies which screens are currently in memory. 138
LA7CE:
	.BYTE	$86,"PTRAD",$C4
	.WORD	LA7A3	; LFA: previous name field in this vocabulary chain
PTRADD:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: CURBLK [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- n1 )
; Manual: Returns the non-updated screen number of the screen most recently
; addressed with BLOCK. Used by the virtual disk interface.
LA7F7:
	.BYTE	$86,"CURBL",$CB
	.WORD	LA7CE	; LFA: previous name field in this vocabulary chain
CURBLK:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: COMBUF [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- a1 )
; Manual: This is the buffer used to send and receive screen data to and from
; the disk drive. This buffer is 1024 bytes long, and is in NON-PAGED memory.
LA80E:
	.BYTE	$86,"COMBU",$C6
	.WORD	LA7F7	; LFA: previous name field in this vocabulary chain
COMBUF:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: BLKTBL [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- a1 )
; Manual: This is a system array variable, which points to the beginning of
; the table indicating the screens that are currently in the memory buffers.
; This array is 32 decimal bytes long.
LA821:
	.BYTE	$86,"BLKTB",$CC
	.WORD	LA80E	; LFA: previous name field in this vocabulary chain
BLKTBL:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: FLUSH [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: This system uses the intelligent version of flush. After a screen
; is written to disk, it is left in memory also, to prevent a screen reread,
; although its UPDATE bit is cleared.
LA836:
	.BYTE	$85,"FLUS",$C8
	.WORD	LA71F	; LFA: previous name field in this vocabulary chain
; Write back dirty active-screen data to its backing slot, then scan all
; sixteen slot tags. Bit 15 marks modified data; LA943 writes the
; corresponding block through R/W and the tag is cleared afterward.
FLUSH:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: GBLOCK [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: This is the main disk interface word in this version of FORTH. It
; performs the screen buffer deblocking, and reads the requested screen n1
; into the user disk buffer from disk of the virtual screen buffers in high
; memory. It also takes care of writing any needed screens to disk as
; required.
LA896:
	.BYTE	$86,"GBLOC",$CB
	.WORD	LA821	; LFA: previous name field in this vocabulary chain
; Select the active screen: if its block differs, preserve the old buffer,
; consult the direct-mapped slot tag, and either copy the cached slot or read
; from the device. Maintain the active header and trailing zero cell.
GBLOCK:
LA8FD:
LA943:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: FORTH [FORTH]; immediate (executes during compilation).
; Implementation: Select the FORTH dictionary through DOVOC. The writable
; instance is copied to $0840 at startup.
; RAM VOCABULARY TEMPLATE. EMPTY copies this region to $0840. DODOE/DOVOC
; select a vocabulary; their latest-name and vocabulary-link cells must
; reside in writable RAM. Literal $0848 references execute the RAM FORTH
; copy, not this ROM template.
LA955:
	.BYTE	$C5,"FORT",$C8
	.WORD	LA9AB	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOVOC
	.WORD	$A081
LA963:
	.WORD	FORTH_BUILTIN_LATEST
	.WORD	0

;	SYSTEM

; Dictionary: SYSTEM [FORTH]; immediate (executes during compilation).
; Implementation: Select the SYSTEM dictionary through DOVOC. Startup copies
; this vocabulary descriptor into RAM.
LA967:
	.BYTE	$C6,"SYSTE",$CD
	.WORD	$840	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOVOC
	.WORD	$A081
LA976:
	.WORD	LBF1A
	.WORD	$850

;	ASSEMBLER

; Dictionary: ASSEMBLER [FORTH]; immediate (executes during compilation).
; Manual: Makes ASSEMBLER the context vocabulary. It will be searched first
; when the input stream is interpreted.
LA97A:
	.BYTE	$C9,"ASSEMBLE",$D2
	.WORD	$852	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOVOC
	.WORD	$A081
LA98C:
	.WORD	LB162
	.WORD	$863

;	EDITOR

; Dictionary: EDITOR [FORTH]; immediate (executes during compilation).
; Implementation: Select the EDITOR dictionary through DOVOC. EDIT also
; installs the editor key-capture table.
LA990:
	.BYTE	$C6,"EDITO",$D2
	.WORD	$865	; LFA: previous name field in this vocabulary chain
EDITOR:
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOVOC
	.WORD	$A081
LA99F:
	.WORD	L9F53
	.WORD	$879

LA9A3:
	.WORD	LA963		; TOP FORTH WORD
	.WORD	LA976		; TOP SYSTEM WORD
	.WORD	LA98C		; TOP ASSEMBLER WORD
	.WORD	LA99F		; TOP EDITOR WORD

;	NOOP

; Dictionary: NOOP [FORTH].
; Implementation: ( -- ) Empty colon definition; immediately returns to its
; caller.
LA9AB:
	.BYTE	$84,"NOO",$D0
	.WORD	LA836	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	SEMIS	; Return to caller thread

;	DLOAD

; Dictionary: DLOAD [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- t )
; Manual: Allows you to load your pre-compiled FORTH dictionary from cassette
; or disk. Used as follows: DLOAD <t> <RETURN> will load a pre-compiled
; dictionary from the cassette file named <t>. To load from disk, preceed the
; word DLOAD with the word DISK as follows: DISK DLOAD <t> <RETURN> Any disk
; file currently open should be closed before performing DLOAD.
LA9B6:
	.BYTE	$85,"DLOA",$C4
	.WORD	$87B	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: DSAVE [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- t )
; Manual: Saves your compiled dictionary to cassette or disk. Used as
; follows: DSAVE <t> <RETURN> will save a pre-compiled dictionary from the
; cassette file named <t>. To save from disk, preceed the word DSAVE with the
; word DISK as follows: DISK DSAVE <t> <RETURN> Any disk file currently open
; should be closed before performing DSAVE.
LA9D6:
	.BYTE	$85,"DSAV",$C5
	.WORD	LA9B6	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: FLOAD [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- <t> )
; Manual: Opens file <t> on current disk drive and loads screen 1. Screen 1
; is expected to load the rest of the file.
LA9FE:
	.BYTE	$85,"FLOA",$C4
	.WORD	LA9D6	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: .FREE [FORTH].
; IMNOTWOPR: reports remaining dictionary space, excluding parser workspace.
; Implementation: ( -- ) Print EM @ minus HERE, the remaining dictionary
; space.
LAA6A:
	.BYTE	$85,".FRE",$C5
	.WORD	LA9FE	; LFA: previous name field in this vocabulary chain
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
LAA80:
	.BYTE	$85
	.BYTE	"TRIA",$C4
	.WORD	LAA6A	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: CLOSE [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: A KERNEL system call, which closes the channel n1 specified to the
; Commodore operating system.
LAAC0:
	.BYTE	$85,"CLOS",$C5
	.WORD	LA896	; LFA: previous name field in this vocabulary chain
CLOSE:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: PROFF [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: Restores character output to the video screen, and turns off the
; serial bus printer channel.
LAAD6:
	.BYTE	$85,"PROF",$C6
	.WORD	LAAC0	; LFA: previous name field in this vocabulary chain
PROFF:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: CHKIN [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: A KERNEL system call, which redirects character input to the
; channel specified as n1. The channel n1 must already be open.
LAB00:
	.BYTE	$85,"CHKI",$CE
	.WORD	LAAD6	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: PRON [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: Opens the serial bus printer channel, and directs all character
; output to that channel. If no printer is connected, the computer may HANG.
LAB1A:
	.BYTE	$84,"PRO",$CE
	.WORD	LAB00	; LFA: previous name field in this vocabulary chain
PRON:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: TRY [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Implementation: ( -- ) Interpret the screen currently held in SCR by
; executing LOAD.
LAB3F:
	.BYTE	$83,"TR",$D9
	.WORD	LAA80	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: PRINT [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- (text) )
; Manual: Sends all character output from the following command line as
; specified by (text) to the serial bus printer.
LAB4F:
	.BYTE	$85,"PRIN",$D4
	.WORD	LAB3F	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: FORGET [FORTH].
; Manual: Executed In the form: FORGET cccc Deletes definition named cccc
; from the dictionary with all entries physically following it. In 64FORTH an
; error message will occur If the CURRENT and CONTEXT vocabularies are not
; currently the same. See FENCE.
LAB61:
	.BYTE	$86,"FORGE",$D4
	.WORD	LAB4F	; LFA: previous name field in this vocabulary chain
FORG:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	TICK
	.WORD	NFA
	.WORD	DUP
	.WORD	FENCE
	.WORD	AT
	.WORD	LESS
	.WORD	LIT	; Push following inline 16-bit cell
	.word	$15	; Inline literal value, not a call
	.WORD	QERR
	.WORD	TOR
	.WORD	VOCL
	.WORD	AT
	.WORD	R
	.WORD	OVER
	.WORD	LESS
	.WORD	ZBRAN,$C	; Pop flag; if zero branch to $AB98 (offset +12 from operand cell)
	.WORD	RAMFTH		; FORTH
	.WORD	DEFIN
	.WORD	AT
	.WORD	BRAN,$FFEE	; Jump to $AB84 (offset -18 from operand cell)
	.WORD	DUP
	.WORD	VOCL
	.WORD	STORE
	.WORD	DUP
	.WORD	LIT,4
	.WORD	SUBB
	.WORD	PFA
	.WORD	LFA
	.WORD	AT
	.WORD	DUP
	.WORD	R
	.WORD	LESS
	.WORD	ZBRAN,$FFF2	; Pop flag; if zero branch to $ABA6 (offset -14 from operand cell)
	.WORD	OVER
	.WORD	TWO
	.WORD	SUBB
	.WORD	STORE
	.WORD	AT
	.WORD	QDUP
	.WORD	ZEQU
	.WORD	ZBRAN,$FFD8	; Pop flag; if zero branch to $AB9E (offset -40 from operand cell)
	.WORD	RFROM
	.WORD	DP
	.WORD	STORE
	.WORD	SEMIS	; Return to caller thread

;	N

; ---------------------------------------------------------------------------
; FORTH-HOSTED 6502 ASSEMBLER
; ---------------------------------------------------------------------------
; Dictionary: N [ASSEMBLER].
; Manual stack: ( --- a1 ) (assembling)
; Manual: Used in a code-definition in the form: N1 - STA, or n2 = )Y ADC, A
; constant which leaves the address of a 9 byte workspace in z-page. Within a
; single code definition, free use may be made over the range N-1 through
; N-7.
LABD0:
	.BYTE	$81,$CE
	.WORD	$84C	; LFA: previous name field in this vocabulary chain
	.WORD	DOCON	; CFA: constant; push the following 16-bit value
	.WORD	N

;	IP

; Dictionary: IP [ASSEMBLER].
; Manual stack: ( --- a1 ) (assembling)
; Manual: Used in a code definition in the form: IP STA, or IP) Y LDA, A
; constant which leaves the address of the pointer to the next FORTH
; execution address in a colon-definition to be interpreted at assembly time.
; At run-time, NEXT moves IP ahead within a colon-definition. Therefore, IP
; points just after the execution address being interpreted. If an in-line
; data structure has been compiled (i.e. a character string), indexing ahead
; by IP can access this data: IP STA, or [P) Y LDA, Loads the third byte
; ahead in the colon-definition being interpreted.
LABD8:
	.BYTE	$82,"I",$D0
	.WORD	LABD0	; LFA: previous name field in this vocabulary chain
	.WORD	DOCON	; CFA: constant; push the following 16-bit value
	.WORD	IP

;	W

; Dictionary: W [ASSEMBLER].
; Manual stack: ( --- a1 ) (assembling)
; Manual: Used in a code definition in the form: W 1+ STA, or W 1 - JMP, or
; W) Y ADC, A constant which leaves at assembly time the address of the
; pointer to the code field (execution address) of the FORTH dictionary word
; being executed. Indexing relative to W can yield any byte in the definition
; parameter field, for example: 3 # LDY, fetches the first byte of the
; parameter field.
LABE1:
	.BYTE	$81,$D7
	.WORD	LABD8	; LFA: previous name field in this vocabulary chain
	.WORD	DOCON	; CFA: constant; push the following 16-bit value
	.WORD	W

;	UP

; Dictionary: UP [ASSEMBLER].
; Manual stack: ( --- a1 ) (assembling)
; Manual: Used in a code definition in the form: UP LDA, or UP) Y STA, A
; constant leaving at assembly time the address of the pointer to the base of
; the user area. For example: HEX 12 # LDY, UP) Y, LDA Loads the low byte of
; the sixth user variable, DP.
LABE9:
	.BYTE	$82,"U",$D0
	.WORD	LABE1	; LFA: previous name field in this vocabulary chain
	.WORD	DOCON	; CFA: constant; push the following 16-bit value
	.WORD	UP

;	XSAVE

; Dictionary: XSAVE [ASSEMBLER].
; Manual stack: ( --- a1 ) (assembling)
; Manual: Used in a code definition in the form: XSAVE STX, or XSAVE LDX, 152
; A constant which leaves the address at assembly time of a temporary buffer
; for saving the X register. Since the X register indexes to the data stack
; in z-page, it must be saved and restored when used for other purposes.
LABF2:
	.BYTE	$85,"XSAV",$C5
	.WORD	LABE9	; LFA: previous name field in this vocabulary chain
	.WORD	DOCON	; CFA: constant; push the following 16-bit value
	.WORD	XSAVE

;	NEXTMP

; Dictionary: NEXTMP [ASSEMBLER].
; Implementation: ( -- addr ) Assembler constant giving the NXTMP zero-page
; address used for indirect dispatch.
LABFE:
	.BYTE	$86,"NEXTM",$D0
	.WORD	LABF2	; LFA: previous name field in this vocabulary chain
	.WORD	DOCON	; CFA: constant; push the following 16-bit value
	.WORD	NXTMP

;	POP

; Dictionary: POP [ASSEMBLER].
; Manual stack: ( --- a1 ) (assembling)
; Manual: ( n1 --- ) (run-time) A constant which leaves (during assembly) the
; machine address of the return point which, at run-time, will pop a 16 bit
; value from the data stack and continue interpretation.
LAC0B:
	.BYTE	$83,"PO",$D0
	.WORD	LABFE	; LFA: previous name field in this vocabulary chain
	.WORD	DOCON	; CFA: constant; push the following 16-bit value
	.WORD	POP

;	POPTWO

; Dictionary: POPTWO [ASSEMBLER].
; Manual stack: ( --- a1 ) (assembling)
; Manual: ( n1/n2 --- ) (run-time) A constant which leaves (during assembly)
; the machine address of the return point, which, at run-time, will pop two
; 16-bit values from the data stack and continue interpretation.
LAC15:
	.BYTE	$86,"POPTW",$CF
	.WORD	LAC0B	; LFA: previous name field in this vocabulary chain
	.WORD	DOCON	; CFA: constant; push the following 16-bit value
	.WORD	POPTWO

;	PUT

; Dictionary: PUT [ASSEMBLER].
; Manual stack: ( --- a1 ) (assembling)
; Manual: ( n1 --- n2 ) (run-time) A constant which leaves (during assembly)
; the machine address of the return point which, at run-time, will write the
; accumulator (as high byte) and the bottom machine stack byte (as low byte)
; over the existing data stack 16-bit value n1.
LAC22:
	.BYTE	$83,"PU",$D4
	.WORD	LAC15	; LFA: previous name field in this vocabulary chain
	.WORD	DOCON	; CFA: constant; push the following 16-bit value
	.WORD	PUT

;	PUSH

; Dictionary: PUSH [ASSEMBLER].
; Manual stack: ( --- a1 ) (assembling)
; Manual: ( --- n1 ) (leaving) A constant which leaves (during assembly) the
; machine address of the return point which, at run-time, will add the
; accumulator (as high byte) and the bottom machine stack byte (as low byte)
; to the data stack.
LAC2C:
	.BYTE	$84,"PUS",$C8
	.WORD	LAC22	; LFA: previous name field in this vocabulary chain
	.WORD	DOCON	; CFA: constant; push the following 16-bit value
	.WORD	PUSH

;	NEXT

; Dictionary: NEXT [ASSEMBLER].
; Manual stack: ( --- a1 ) (assembling)
; Manual: A constant which leaves the machine address of the FORTH address
; interpreter. All code definitions must return execution to NEXT, or code
; that returns to NEXT (that is, PUSH, PUT, POP, POPTWO).
LAC37:
	.BYTE	$84,"NEX",$D4
	.WORD	LAC2C	; LFA: previous name field in this vocabulary chain
	.WORD	DOCON	; CFA: constant; push the following 16-bit value
	.WORD	NEXT

;	SETUP

; Dictionary: SETUP [ASSEMBLER].
; Implementation: ( -- addr ) Assembler constant giving the address of the
; native SETUP helper. See the native entry for A/Y inputs and clobbered
; scratch space.
LAC42:
	.BYTE	$85,"SETU",$D0
	.WORD	LAC37	; LFA: previous name field in this vocabulary chain
	.WORD	DOCON	; CFA: constant; push the following 16-bit value
	.WORD	SETUP

;	INDEX

; Dictionary: INDEX [ASSEMBLER].
; Manual stack: ( --- a1 ) (assembling)
; Manual: An array used within the assembler, which holds bit patterns of
; allowable addressing modes.
LAC4E:
	.BYTE	$85,"INDE",$D8
	.WORD	LAC42	; LFA: previous name field in this vocabulary chain
; Assembler opcode adjustment table: indexed by addressing-mode selection.
; $80 marks an unavailable combination. M/CPU combines these offsets with an
; instruction family base and validates mode masks before emitting bytes.
INDEX:
	.WORD	DOVAR	; CFA: variable; push the parameter-field address
	.BYTE	$09,$09,$05,$15,$15,$01,$11,$80
	.BYTE	$09,$80,$0D,$1D,$19,$80,$80,$80
	.BYTE	$80,$00,$04,$14,$14,$80,$80,$80
	.BYTE	$80,$80,$0C,$1C,$1C,$80,$80,$2C

;	MODE

; Dictionary: MODE [ASSEMBLER].
; Manual stack: ( --- a1 )
; Manual: A user variable used within the assembler, which holds a flag
; indicating the addressing mode of the op-code being generated. 135
LAC78:
	.BYTE	$84,"MOD",$C5
	.WORD	LAC4E	; LFA: previous name field in this vocabulary chain
; LISTING/MANUAL DIFFERENCE: the bytes here are $02,$02, and DOUSE reads only
; the first. This ROM therefore returns UP+$02 ($0942), whereas the manual
; user-variable table lists MODE at $0A0A (offset $CA). The original bytes
; are preserved.
MODE:
	.WORD	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.BYTE	$02	; User offset $0002; initial address $0942
	.BYTE	$02

;	.A

; Dictionary: .A [ASSEMBLER].
; Implementation: Assembler mode selector: set MODE to 0 for accumulator
; addressing.
LAC83:
	.BYTE	$82,".",$C1
	.WORD	LAC78	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	ZERO
	.WORD	MODE
	.WORD	STORE
	.WORD	SEMIS	; Return to caller thread

;	#

; Dictionary: # [ASSEMBLER].
; Manual stack: ( --- )
; Manual: Specify 'immediate' addressing mode for the next op-code generated.
LAC92:
	.BYTE	$81,$A3
	.WORD	LAC83	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	ONE
	.WORD	MODE
	.WORD	STORE
	.WORD	SEMIS	; Return to caller thread

;	MEM

; Dictionary: MEM [ASSEMBLER].
; Manual: Used with the assembler to set MODE to the default value for direct
; memory addressing, z-page.
LACA0:
	.BYTE	$83,"ME",$CD
	.WORD	LAC92	; LFA: previous name field in this vocabulary chain
MEM:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	TWO
	.WORD	MODE
	.WORD	STORE
	.WORD	SEMIS	; Return to caller thread

;	,X

; Dictionary: ,X [ASSEMBLER].
; Manual stack: ( --- )
; Manual: Specify 'indexed X' addressing mode for the next op-code generated.
LACB0:
	.BYTE	$82,",",$D8
	.WORD	LACA0	; LFA: previous name field in this vocabulary chain
LACB5:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	THREE
	.WORD	MODE
	.WORD	STORE
	.WORD	SEMIS	; Return to caller thread

;	,Y

; Dictionary: ,Y [ASSEMBLER].
; Implementation: Assembler mode selector: set MODE to 4 for Y-indexed memory
; addressing.
LACBF:
	.BYTE	$82,",",$D9
	.WORD	LACB0	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	LIT,4
	.WORD	MODE
	.WORD	STORE
	.WORD	SEMIS	; Return to caller thread

;	X)

; Dictionary: X) [ASSEMBLER].
; Manual: Specify 'indexed indirect X' addressing mode for the next op-code
; generated.
LACD0:
	.BYTE	$82,"X",$A9
	.WORD	LACBF	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	LIT,5
	.WORD	MODE
	.WORD	STORE
	.WORD	SEMIS	; Return to caller thread

;	)Y

; Dictionary: )Y [ASSEMBLER].
; Manual stack: ( --- )
; Manual: Specify 'indirect indexed Y' addressing mode for the next op-code
; generated.
LACE1:
	.BYTE	$82,")",$D9
	.WORD	LACD0	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	LIT,6
	.WORD	MODE
	.WORD	STORE
	.WORD	SEMIS	; Return to caller thread

;	)

; Dictionary: ) [ASSEMBLER].
; Manual stack: ( --- )
; Manual: Specify 'indirect' addressing for the next op-code generated. Used
; only on the JMP instructions.
LACF2:
	.BYTE	$81,$A9
	.WORD	LACE1	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	LIT,$F
	.WORD	MODE
	.WORD	STORE
	.WORD	SEMIS	; Return to caller thread

;	BOT

; Dictionary: BOT [ASSEMBLER].
; Manual stack: ( --- n1 )
; Manual: Used during code assembly in the form: BOT LDA, or BOT X) STA,
; Addresses the bottom of the data stack (containing the low byte) by
; selecting the X mode and leaving n1=0 at assembly time. This value of n1
; may be modified to another byte offset Into the data stack. Must be
; followed by a multi-mode op-code mnemonic.
LAD02:
	.BYTE	$83,"BO",$D4
	.WORD	LACF2	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	LACB5
	.WORD	ZERO
	.WORD	SEMIS	; Return to caller thread

;	SEC

; Dictionary: SEC [ASSEMBLER].
; Manual stack: ( --- n1 ) (assembling)
; Manual: Identical to BOT, except that n1=2. Addressing the low byte of the
; second 16-bit data stack value (third byte on the low data stack).
LAD10:
	.BYTE	$83,"SE",$C3
	.WORD	LAD02	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	LACB5
	.WORD	TWO
	.WORD	SEMIS	; Return to caller thread

;	RP)

; Dictionary: RP) [ASSEMBLER].
; Manual stack: ( --- n1 ) (assembly-time)
; Manual: Used in the code definition in the form: RP) LDA, or RP) 3 + STA,
; Addresses the bottom byte of the return stack (containing the low byte) by
; selecting X mode and leaving n1=$0101. N1 may be modified to another byte
; offset. Before operating on the return stack the X register must be saved
; in XSAVE and TSX, must be executed; before returning to NEXT, the X
; register must be restored.
LAD1E:
	.BYTE	$83,"RP",$A9
	.WORD	LAD10	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	LACB5
	.WORD	LIT,$101
	.WORD	SEMIS	; Return to caller thread

;	UPMODE

; Dictionary: UPMODE [ASSEMBLER].
; Implementation: Assembler helper: upgrade the mode when needed, construct
; its mode-mask bit and report whether the instruction descriptor permits it.
LAD2E:
	.BYTE	$86,"UPMOD",$C5
	.WORD	LAD1E	; LFA: previous name field in this vocabulary chain
UPMODE:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	ZBRAN,$1A	; Pop flag; if zero branch to $AD55 (offset +26 from operand cell)
	.WORD	MODE
	.WORD	AT
	.WORD	LIT,8
	.WORD	ANDD
	.WORD	ZEQU
	.WORD	ZBRAN,$A	; Pop flag; if zero branch to $AD55 (offset +10 from operand cell)
	.WORD	LIT,8
	.WORD	MODE
	.WORD	PSTOR
	.WORD	ONE
	.WORD	MODE
	.WORD	AT
	.WORD	LIT,$F
	.WORD	ANDD
	.WORD	QDUP
	.WORD	ZBRAN,$E	; Pop flag; if zero branch to $AD73 (offset +14 from operand cell)
	.WORD	ZERO
	.WORD	PDO
	.WORD	DUP
	.WORD	PLUS
	.WORD	PLOOP,$FFFA	; Increment loop index; if continuing branch to $AD6B (offset -6 from operand cell)
	.WORD	OVER
	.WORD	ONEP
	.WORD	AT
	.WORD	ANDD
	.WORD	ZEQU
	.WORD	SEMIS	; Return to caller thread

;	CPU

; Dictionary: CPU [ASSEMBLER].
; Manual stack: ( n1 --- ) (compiling assembler)
; Manual: An assembler defining word used to create assembler mnemonics that
; have only one addressing mode: EA CPU NOP, CPU creates the word NOP, with
; its op-code EA as a parameter. When NOP is later executed, it assembles EA
; as a one byte op-code. 118
LAD7F:
	.BYTE	$83,"CP",$D5
	.WORD	LAD2E	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	BUILD
	.WORD	CCOM
	.WORD	DOES
; DOES> behavior for single-byte assembler instructions: fetch the instance
; opcode, compile it with C-comma, then reset addressing mode with MEM.
DOCPU:
	.WORD	CAT
	.WORD	CCOM
	.WORD	MEM
	.WORD	SEMIS	; Return to caller thread

;	BRK,

; Dictionary: BRK, [ASSEMBLER].
; Assembler word: emit the 6502 BRK instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LAD95:
	.BYTE	$84,"BRK",$AC
	.WORD	LAD7F	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOCPU
	.BYTE	0

;	CLC,

; Dictionary: CLC, [ASSEMBLER].
; Assembler word: emit the 6502 CLC instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LADA1:
	.BYTE	$84,"CLC",$AC
	.WORD	LAD95	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOCPU
	.BYTE	$18

;	CLD,

; Dictionary: CLD, [ASSEMBLER].
; Assembler word: emit the 6502 CLD instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LADAD:
	.BYTE	$84,"CLD",$AC
	.WORD	LADA1	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOCPU
	.BYTE	$D8

;	CLI,

; Dictionary: CLI, [ASSEMBLER].
; Assembler word: emit the 6502 CLI instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LADB9:
	.BYTE	$84,"CLI",$AC
	.WORD	LADAD	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOCPU
	.BYTE	$58

;	CLV,

; Dictionary: CLV, [ASSEMBLER].
; Assembler word: emit the 6502 CLV instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LADC5:
	.BYTE	$84,"CLV",$AC
	.WORD	LADB9	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOCPU
	.BYTE	$B8

;	DEX,

; Dictionary: DEX, [ASSEMBLER].
; Assembler word: emit the 6502 DEX instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LADD1:
	.BYTE	$84,"DEX",$AC
	.WORD	LADC5	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOCPU
	.BYTE	$CA

;	DEY,

; Dictionary: DEY, [ASSEMBLER].
; Assembler word: emit the 6502 DEY instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LADDD:
	.BYTE	$84,"DEY",$AC
	.WORD	LADD1	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOCPU
	.BYTE	$88

;	INX,

; Dictionary: INX, [ASSEMBLER].
; Assembler word: emit the 6502 INX instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LADE9:
	.BYTE	$84,"INX",$AC
	.WORD	LADDD	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOCPU
	.BYTE	$E8

;	INY,

; Dictionary: INY, [ASSEMBLER].
; Assembler word: emit the 6502 INY instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LADF5:
	.BYTE	$84,"INY",$AC
	.WORD	LADE9	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOCPU
	.BYTE	$C8

;	NOP,

; Dictionary: NOP, [ASSEMBLER].
; Assembler word: emit the 6502 NOP instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LAE01:
	.BYTE	$84,"NOP",$AC
	.WORD	LADF5	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOCPU
	.BYTE	$EA

;	PHA,

; Dictionary: PHA, [ASSEMBLER].
; Assembler word: emit the 6502 PHA instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LAE0D:
	.BYTE	$84,"PHA",$AC
	.WORD	LAE01	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOCPU
	.BYTE	$48

;	PHP,

; Dictionary: PHP, [ASSEMBLER].
; Assembler word: emit the 6502 PHP instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LAE19:
	.BYTE	$84,"PHP",$AC
	.WORD	LAE0D	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOCPU
	.BYTE	8

;	PLA,

; Dictionary: PLA, [ASSEMBLER].
; Assembler word: emit the 6502 PLA instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LAE25:
	.BYTE	$84,"PLA",$AC
	.WORD	LAE19	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOCPU
	.BYTE	$68

;	PLP,

; Dictionary: PLP, [ASSEMBLER].
; Assembler word: emit the 6502 PLP instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LAE31:
	.BYTE	$84,"PLP",$AC
	.WORD	LAE25	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOCPU
	.BYTE	$28

;	RTI,

; Dictionary: RTI, [ASSEMBLER].
; Assembler word: emit the 6502 RTI instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LAE3D:
	.BYTE	$84,"RTI",$AC
	.WORD	LAE31	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOCPU
	.BYTE	$40

;	RTS,

; Dictionary: RTS, [ASSEMBLER].
; Assembler word: emit the 6502 RTS instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LAE49:
	.BYTE	$84,"RTS",$AC
	.WORD	LAE3D	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOCPU
	.BYTE	$60

;	SEC,

; Dictionary: SEC, [ASSEMBLER].
; Assembler word: emit the 6502 SEC instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LAE55:
	.BYTE	$84,"SEC",$AC
	.WORD	LAE49	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOCPU
	.BYTE	$38

;	SED,

; Dictionary: SED, [ASSEMBLER].
; Assembler word: emit the 6502 SED instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LAE61:
	.BYTE	$84,"SED",$AC
	.WORD	LAE55	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOCPU
	.BYTE	$F8

;	SEI,

; Dictionary: SEI, [ASSEMBLER].
; Assembler word: emit the 6502 SEI instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LAE6D:
	.BYTE	$84,"SEI",$AC
	.WORD	LAE61	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOCPU
	.BYTE	$78

;	TAX,

; Dictionary: TAX, [ASSEMBLER].
; Assembler word: emit the 6502 TAX instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LAE79:
	.BYTE	$84,"TAX",$AC
	.WORD	LAE6D	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOCPU
	.BYTE	$AA

;	TAY,

; Dictionary: TAY, [ASSEMBLER].
; Assembler word: emit the 6502 TAY instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LAE85:
	.BYTE	$84,"TAY",$AC
	.WORD	LAE79	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOCPU
	.BYTE	$A8

;	TSX,

; Dictionary: TSX, [ASSEMBLER].
; Assembler word: emit the 6502 TSX instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LAE91:
	.BYTE	$84,"TSX",$AC
	.WORD	LAE85	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOCPU
	.BYTE	$BA

;	TXA,

; Dictionary: TXA, [ASSEMBLER].
; Assembler word: emit the 6502 TXA instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LAE9D:
	.BYTE	$84,"TXA",$AC
	.WORD	LAE91	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOCPU
	.BYTE	$8A

;	TXS,

; Dictionary: TXS, [ASSEMBLER].
; Assembler word: emit the 6502 TXS instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LAEA9:
	.BYTE	$84,"TXS",$AC
	.WORD	LAE9D	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOCPU
	.BYTE	$9A

;	TYA,

; Dictionary: TYA, [ASSEMBLER].
; Assembler word: emit the 6502 TYA instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LAEB5:
	.BYTE	$84,"TYA",$AC
	.WORD	LAEA9	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOCPU
	.BYTE	$98

;	M/CPU

; Dictionary: M/CPU [ASSEMBLER].
; Manual stack: ( n1/n2 --- ) (compiling assembler)
; Manual: An assembler defining word used to create assembler mnemonics that
; have multiple address modes HEX 1C6E 60 M/CPU ADC, M/CPU creates the word
; ADC, with two parameters. When ADC later executes, it uses these
; parameters, along with stack values and the contents of MODE to calculate
; and assemble the correct op-code operands. 134
LAEC1:
	.BYTE	$85,"M/CP",$D5
	.WORD	LAEB5	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	BUILD
	.WORD	CCOM
	.WORD	COMMA
	.WORD	DOES
; DOES> behavior for instructions with operands: instance data holds base
; opcode plus addressing-mode masks. Select zero-page/absolute form, validate
; the mode, compile the opcode and the needed operand bytes, then restore MEM
; mode.
DOMCPU:
	.WORD	DUP
	.WORD	ONEP
	.WORD	AT
	.WORD	LIT,$80
	.WORD	ANDD
	.WORD	ZBRAN,$A	; Pop flag; if zero branch to $AEEB (offset +10 from operand cell)
	.WORD	LIT,$10
	.WORD	MODE
	.WORD	PSTOR
	.WORD	OVER
	.WORD	LIT,$FF00
	.WORD	ANDD
	.WORD	UPMODE
	.WORD	UPMODE
	.WORD	ZBRAN,$E	; Pop flag; if zero branch to $AF07 (offset +14 from operand cell)
	.WORD	MEM
	.WORD	CR
	.WORD	LATES
	.WORD	IDDOT
	.WORD	THREE
	.WORD	ERROR
	.WORD	CAT
	.WORD	MODE
	.WORD	CAT
	.WORD	INDEX
	.WORD	PLUS
	.WORD	CAT
	.WORD	PLUS
	.WORD	CCOM
	.WORD	MODE
	.WORD	CAT
	.WORD	LIT,7
	.WORD	ANDD
	.WORD	ZBRAN,$1E	; Pop flag; if zero branch to $AF41 (offset +30 from operand cell)
	.WORD	MODE
	.WORD	CAT
	.WORD	LIT,$F
	.WORD	ANDD
	.WORD	LIT,7
	.WORD	LESS
	.WORD	ZBRAN,8	; Pop flag; if zero branch to $AF3F (offset +8 from operand cell)
	.WORD	CCOM
	.WORD	BRAN,4	; Jump to $AF41 (offset +4 from operand cell)
	.WORD	COMMA
	.WORD	MEM
	.WORD	SEMIS	; Return to caller thread

;	ADC,

; Dictionary: ADC, [ASSEMBLER].
; Assembler word: emit the 6502 ADC instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LAF45:
	.BYTE	$84,"ADC",$AC
	.WORD	LAEC1	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOMCPU
	.BYTE	$60,$6E,$1C

;	AND,

; Dictionary: AND, [ASSEMBLER].
; Assembler word: emit the 6502 AND instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LAF53:
	.BYTE	$84,"AND",$AC
	.WORD	LAF45	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOMCPU
	.BYTE	$20,$6E,$1C

;	CMP,

; Dictionary: CMP, [ASSEMBLER].
; Assembler word: emit the 6502 CMP instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LAF61:
	.BYTE	$84,"CMP",$AC
	.WORD	LAF53	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOMCPU
	.BYTE	$C0,$6E,$1C

;	EOR,

; Dictionary: EOR, [ASSEMBLER].
; Assembler word: emit the 6502 EOR instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LAF6F:
	.BYTE	$84,"EOR",$AC
	.WORD	LAF61	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOMCPU
	.BYTE	$40,$6E,$1C

;	LDA,

; Dictionary: LDA, [ASSEMBLER].
; Assembler word: emit the 6502 LDA instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LAF7D:
	.BYTE	$84,"LDA",$AC
	.WORD	LAF6F	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOMCPU
	.BYTE	$A0,$6E,$1C

;	ORA,

; Dictionary: ORA, [ASSEMBLER].
; Assembler word: emit the 6502 ORA instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LAF8B:
	.BYTE	$84,"ORA",$AC
	.WORD	LAF7D	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOMCPU
	.BYTE	$00,$6E,$1C

;	SBC,

; Dictionary: SBC, [ASSEMBLER].
; Assembler word: emit the 6502 SBC instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LAF99:
	.BYTE	$84,"SBC",$AC
	.WORD	LAF8B	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOMCPU
	.BYTE	$E0,$6E,$1C

;	STA,

; Dictionary: STA, [ASSEMBLER].
; Assembler word: emit the 6502 STA instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LAFA7:
	.BYTE	$84,"STA",$AC
	.WORD	LAF99	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOMCPU
	.BYTE	$80,$6C,$1C

;	ASL,

; Dictionary: ASL, [ASSEMBLER].
; Assembler word: emit the 6502 ASL instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LAFB5:
	.BYTE	$84,"ASL",$AC
	.WORD	LAFA7	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOMCPU
	.BYTE	$01,$0D,$0D

;	DEC,

; Dictionary: DEC, [ASSEMBLER].
; Assembler word: emit the 6502 DEC instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LAFC3:
	.BYTE	$84,"DEC",$AC
	.WORD	LAFB5	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOMCPU
	.BYTE	$C1,$0C,$0C

;	INC,

; Dictionary: INC, [ASSEMBLER].
; Assembler word: emit the 6502 INC instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LAFD1:
	.BYTE	$84,"INC",$AC
	.WORD	LAFC3	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOMCPU
	.BYTE	$E1,$0C,$0C

;	LSR,

; Dictionary: LSR, [ASSEMBLER].
; Assembler word: emit the 6502 LSR instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LAFDF:
	.BYTE	$84,"LSR",$AC
	.WORD	LAFD1	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOMCPU
	.BYTE	$41,$0D,$0D

;	ROL,

; Dictionary: ROL, [ASSEMBLER].
; Assembler word: emit the 6502 ROL instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LAFED:
	.BYTE	$84,"ROL",$AC
	.WORD	LAFDF	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOMCPU
	.BYTE	$21,$0D,$0D

;	ROR,

; Dictionary: ROR, [ASSEMBLER].
; Assembler word: emit the 6502 ROR instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LAFFB:
	.BYTE	$84,"ROR",$AC
	.WORD	LAFED	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOMCPU
	.BYTE	$61,$0D,$0D

;	STX,

; Dictionary: STX, [ASSEMBLER].
; Assembler word: emit the 6502 STX instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LB009:
	.BYTE	$84,"STX",$AC
	.WORD	LAFFB	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOMCPU
	.BYTE	$81,$14,$04

;	CPX,

; Dictionary: CPX, [ASSEMBLER].
; Assembler word: emit the 6502 CPX instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LB017:
	.BYTE	$84,"CPX",$AC
	.WORD	LB009	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOMCPU
	.BYTE	$E0,$86,$04

;	CPY,

; Dictionary: CPY, [ASSEMBLER].
; Assembler word: emit the 6502 CPY instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LB025:
	.BYTE	$84,"CPY",$AC
	.WORD	LB017	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOMCPU
	.BYTE	$C0,$86,$04

;	LDX,

; Dictionary: LDX, [ASSEMBLER].
; Assembler word: emit the 6502 LDX instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LB033:
	.BYTE	$84,"LDX",$AC
	.WORD	LB025	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOMCPU
	.BYTE	$A2,$96,$14

;	LDY,

; Dictionary: LDY, [ASSEMBLER].
; Assembler word: emit the 6502 LDY instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LB041:
	.BYTE	$84,"LDY",$AC
	.WORD	LB033	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOMCPU
	.BYTE	$A0,$8E,$0C

;	STY,

; Dictionary: STY, [ASSEMBLER].
; Assembler word: emit the 6502 STY instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LB04F:
	.BYTE	$84,"STY",$AC
	.WORD	LB041	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOMCPU
	.BYTE	$80,$8C,$04

;	JSR,

; Dictionary: JSR, [ASSEMBLER].
; Assembler word: emit the 6502 JSR instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LB05D:
	.BYTE	$84,"JSR",$AC
	.WORD	LB04F	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOMCPU
	.BYTE	$14,$80,$04

;	JMP,

; Dictionary: JMP, [ASSEMBLER].
; Assembler word: emit the 6502 JMP instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LB06B:
	.BYTE	$84,"JMP",$AC
	.WORD	LB05D	; LFA: previous name field in this vocabulary chain
JMPP:
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOMCPU
	.BYTE	$40,$80,$84

;	BIT,

; Dictionary: BIT, [ASSEMBLER].
; Assembler word: emit the 6502 BIT instruction into the RAM dictionary. The
; DODOE behavior below selects operand encoding where applicable; these
; instance bytes are opcode data, not instructions executed here.
LB079:
	.BYTE	$84,"BIT",$AC
	.WORD	LB06B	; LFA: previous name field in this vocabulary chain
	.WORD	DODOE	; CFA: DOES> word; behavior pointer then instance data
	.WORD	DOMCPU
	.BYTE	$84,$00,$00

;	BEGIN,

; Dictionary: BEGIN, [ASSEMBLER]; immediate (executes during compilation).
; Manual stack: ( --- a1/n1 ) (assembling)
; Manual: ( --- ) (run-time) Occurs in a code definition in the form: BEGIN,
; ... n2 UNTIL, At run-time, BEGIN, leaves the dictionary pointer address a1
; and the value n1-1 for later testing of conditional pairing by UNTIL,.
LB087:
	.BYTE	$C6,"BEGIN",$AC
	.WORD	LB079	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	HERE
	.WORD	ONE
	.WORD	SEMIS	; Return to caller thread

;	UNTIL,

; Dictionary: UNTIL, [ASSEMBLER]; immediate (executes during compilation).
; Manual stack: ( a1/n1/n2 --- ) (assembling)
; Manual: ( --- ) (run-time) Occurs in a code definition in the form: BEGIN
; .... n2 UNTIL, At run-time, UNTIL, controls the conditional branching back
; to BEGIN,. If the processor status bit specified by condition code n=2 is
; false, execution returns to BEGIN,; otherwise execution continues ahead. At
; assembly time, UNTIL, assembles a conditional relative branch to address
; a1, based on condition code n2. The number n1=1, and is used for error
; checking.
LB098:
	.BYTE	$C6,"UNTIL",$AC
	.WORD	LB087	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	QEXEC
	.WORD	TOR
	.WORD	ONE
	.WORD	QPAIR
	.WORD	RFROM
	.WORD	CCOM
	.WORD	HERE
	.WORD	ONEP
	.WORD	SUBB
	.WORD	CCOM
	.WORD	SEMIS	; Return to caller thread

;	IF,

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
LB0B9:
	.BYTE	$C3,"IF",$AC
	.WORD	LB098	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	CCOM
	.WORD	HERE
	.WORD	ZERO
	.WORD	CCOM
	.WORD	TWO
	.WORD	SEMIS	; Return to caller thread

;	ENDIF,

; Dictionary: ENDIF, [ASSEMBLER]; immediate (executes during compilation).
; Manual stack: ( a1/n1 --- ) (assembly-time)
; Manual: ( --- ) Occurs in a code definition in the form: n2 IF, (true part)
; ELSE, (false part) ENDIF, At run-time ENDIF, marks the conclusion of a
; conditional structure. Execution of either the true part or the false part
; resumes the following ENDIF,. When assembling, address all and n1=2 are
; used to resolve the pending forward branch to ENDIF,.
LB0CD:
	.BYTE	$C6,"ENDIF",$AC
	.WORD	LB0B9	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	QEXEC
	.WORD	TWO
	.WORD	QPAIR
	.WORD	HERE
	.WORD	OVER
	.WORD	CAT
	.WORD	ZBRAN,$A	; Pop flag; if zero branch to $B0F0 (offset +10 from operand cell)
	.WORD	SWAP
	.WORD	STORE
	.WORD	BRAN,$C	; Jump to $B0FA (offset +12 from operand cell)
	.WORD	OVER
	.WORD	ONEP
	.WORD	SUBB
	.WORD	SWAP
	.WORD	CSTOR
	.WORD	SEMIS	; Return to caller thread

;	ELSE,

; Dictionary: ELSE, [ASSEMBLER]; immediate (executes during compilation).
; Manual stack: ( --- a1/n1 ) (assembling)
; Manual: ( --- ) (run-time) Occurs within a code definition in the form: n2
; IF, (true part) ELSE, (false part) ENDIF, At run-time, if the condition
; code specified by n2 is false, execution skips to the machine code
; following ELSE,. At assembly time ELSE, assembles a forward jump to just
; after ENDIF, and resolves a pending forward branch from IF,. The values
; n1=n2 are used for error checking of conditional pairing.
LB0FC:
	.BYTE	$C5,"ELSE",$AC
	.WORD	LB0CD	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	TWO
	.WORD	QPAIR
	.WORD	HERE
	.WORD	ONEP
	.WORD	ONE
	.WORD	JMPP
	.WORD	SWAP
	.WORD	HERE
	.WORD	OVER
	.WORD	ONEP
	.WORD	SUBB
	.WORD	SWAP
	.WORD	CSTOR
	.WORD	TWO
	.WORD	SEMIS	; Return to caller thread

;	NOT

; Dictionary: NOT [ASSEMBLER].
; Manual stack: ( n1 --- n2 ) (assembly-time)
; Manual: When assembling, reverse the condition code n1 for the following
; conditional, returning n2 the complemented condition code. For example: 0
; NOT IF, (true part) ENDIF, will branch based on "not equal to zero."
LB124:
	.BYTE	$83,"NO",$D4
	.WORD	LB0FC	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	LIT,$20
	.WORD	PLUS
	.WORD	SEMIS	; Return to caller thread

;	CS

; Dictionary: CS [ASSEMBLER].
; Manual stack: ( --- n1 ) (assembling)
; Manual: Specify that the Immediately following conditional will branch
; based on if the processor carry is set (C=1). The flag n1 is left at
; assembly time; there is no run-time effect on the stack.
LB134:
	.BYTE	$82,"C",$D3
	.WORD	LB124	; LFA: previous name field in this vocabulary chain
	.WORD	DOCON	; CFA: constant; push the following 16-bit value
	.WORD	$90

;	0=

; Dictionary: 0= [ASSEMBLER].
; Manual stack: ( --- n1 ) (assembling)
; Manual: Specify that the immediately following conditional will branch
; based on the processor status bit being equal to zero (Z=1). The flag n1 is
; left at assembly time; there is no run-time effect on the stack.
LB13D:
	.BYTE	$82,"0",$BD
	.WORD	LB134	; LFA: previous name field in this vocabulary chain
	.WORD	DOCON	; CFA: constant; push the following 16-bit value
	.WORD	$D0

;	0<

; Dictionary: 0< [ASSEMBLER].
; Manual stack: ( --- n1 ) (assembling)
; Manual: Specify that the immediately following conditional will branch
; based on the processor status bit being negative (N=1), i.e., less than
; zero. The flag n1 is left at assembly time; there is no run-time effect on
; the stack.
LB146:
	.BYTE	$82,"0",$BC
	.WORD	LB13D	; LFA: previous name field in this vocabulary chain
	.WORD	DOCON	; CFA: constant; push the following 16-bit value
	.WORD	$10

;	>=

; Dictionary: >= [ASSEMBLER].
; Manual stack: ( --- n1 ) (assembling)
; Manual: Specify that the immediately following conditional will branch
; based on the processor status bit carry being set (see =1). The flag n1 is
; left at assembly time. There is no run-time effect on the stack.
LB14F:
	.BYTE	$82,">",$BD
	.WORD	LB146	; LFA: previous name field in this vocabulary chain
	.WORD	DOCON	; CFA: constant; push the following 16-bit value
	.WORD	$90

;	OVS

; Dictionary: OVS [ASSEMBLER].
; Manual stack: ( --- n1 ) (assembling)
; Manual: Specify that the immediately following conditional branch based on
; the processor overflow flag is set (V=1). The flag n1 is left at assembly
; time; there is no run-time effect on the stack.
LB158:
	.BYTE	$83,"OV",$D3
	.WORD	LB14F	; LFA: previous name field in this vocabulary chain
	.WORD	DOCON	; CFA: constant; push the following 16-bit value
	.WORD	$70

;	END-CODE

; Dictionary: END-CODE [ASSEMBLER]; immediate (executes during compilation).
; Manual: An error check word marking the end of a CODE definition.
; Successful execution to and including END-CODE will unSMUDGE the most
; recent CURRENT vocabulary definition, making it available for execution.
; END-CODE also exits the ASSEMBLER making CONTEXT the same as CURRENT. This
; word previously was named C;.
LB162:
	.BYTE	$C8,"END-COD",$C5
	.WORD	LB158	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	CURR
	.WORD	AT
	.WORD	CONT
	.WORD	STORE
	.WORD	QEXEC
	.WORD	QCSP
	.WORD	SMUDGE
	.WORD	SEMIS	; Return to caller thread

;	CODE

; Dictionary: CODE [FORTH]; immediate (executes during compilation).
; Manual stack: ( --- t )
; Manual: A defining word used in the form: CODE (name) ... END-CODE To
; create a dictionary entry for (name) in the CURRENT vocabulary. Name's code
; field contains the address of the parameter field. When (name) Is later
; executed, the machine code in this parameter field will execute. The
; CONTEXT vocabulary is made ASSEMBLER, to make available op-code mnemonics.
LB17F:
	.BYTE	$C4,"COD",$C5
	.WORD	LAB61	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	QEXEC
	.WORD	CREAT
	.WORD	$871
	.WORD	MEM
	.WORD	SCSP
	.WORD	SEMIS	; Return to caller thread

;	DEPTH

; Dictionary: DEPTH [FORTH].
; Manual stack: ( --- n1 )
; Manual: Returns the current depth of the data stack as value n1. The actual
; depth of the stack is increased by one element.
LB194:
	.BYTE	$85,"DEPT",$C8
	.WORD	LB17F	; LFA: previous name field in this vocabulary chain
DEPTH:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	SPAT
	.WORD	LIT,TOS
	.WORD	SWAP
	.WORD	SUBB
	.WORD	TWO
	.WORD	SLASH
	.WORD	SEMIS	; Return to caller thread

;	.S

; Dictionary: .S [FORTH].
; Manual stack: ( --- )
; Manual: Prints the current contents of the data stack on the screen in the
; current base, without destroying its contents.
LB1AE:
	.BYTE	$82,".",$D3
	.WORD	LB194	; LFA: previous name field in this vocabulary chain
DOTS:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	QSTAC
	.WORD	DEPTH
	.WORD	ZBRAN,$24	; Pop flag; if zero branch to $B1DF (offset +36 from operand cell)
	.WORD	SPAT
	.WORD	TWO
	.WORD	SUBB
	.WORD	LIT,$5E
	.WORD	PDO
	.WORD	I
	.WORD	AT
	.WORD	LIT,5
	.WORD	DOTR
	.WORD	LIT,$FFFE
	.WORD	PPLOO,$FFF0	; Add stack increment; if continuing branch to $B1C9 (offset -16 from operand cell)
	.WORD	BRAN,$C	; Jump to $B1E9 (offset +12 from operand cell)
	.WORD	PDOTQ	; Print counted inline text; resume after its payload
	.BYTE	7
	.BYTE	" EMPTY "
	.WORD	SEMIS	; Return to caller thread

;	ERP

; ---------------------------------------------------------------------------
; FORTH SINGLE-STEPPER AND DECOMPILER
; ---------------------------------------------------------------------------
; Dictionary: ERP [SYSTEM].
; Manual: One of a group of EMULATION words, used by the DEBUGGER. Not a user
; word. 126
LB1EB:
	.BYTE	$83,"ER",$D0
	.WORD	LAB1A	; LFA: previous name field in this vocabulary chain
ERP:
	.WORD	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.WORD	$CC	; User offset $00CC; initial address $0A0C

;	EIP

; Dictionary: EIP [SYSTEM].
; Manual: One of a group of EMULATION words, used by the DEBUGGER. Not a user
; word.
LB1F5:
	.BYTE	$83,"EI",$D0
	.WORD	LB1EB	; LFA: previous name field in this vocabulary chain
EIP:
	.WORD	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.WORD	$CE	; User offset $00CE; initial address $0A0E

;	ERP!

; Dictionary: ERP! [SYSTEM].
; Manual: One of a group of EMULATION words, used by the DEBUGGER. Not a user
; word.
LB1FF:
	.BYTE	$84,"ERP",$A1
	.WORD	LB1F5	; LFA: previous name field in this vocabulary chain
ERPSTO:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	BLKTBL
	.WORD	TWO
	.WORD	SUBB
	.WORD	ERP
	.WORD	STORE
	.WORD	SEMIS	; Return to caller thread

;	E>R

; Dictionary: E>R [SYSTEM].
; Manual: One of a group of EMULATION words, used by the DEBUGGER. Not a user
; word.
LB214:
	.BYTE	$83,"E>",$D2
	.WORD	LB1FF	; LFA: previous name field in this vocabulary chain
ETOR:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	ERP
	.WORD	AT
	.WORD	STORE
	.WORD	LIT,$FFFE
	.WORD	ERP
	.WORD	PSTOR
	.WORD	SEMIS	; Return to caller thread

;	ER>

; Dictionary: ER> [SYSTEM].
; Manual: One of a group of EMULATION words, used by the DEBUGGER. Not a user
; word.
LB22C:
	.BYTE	$83,"ER",$BE
	.WORD	LB214	; LFA: previous name field in this vocabulary chain
ERFROM:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	TWO
	.WORD	ERP
	.WORD	PSTOR
	.WORD	ERP
	.WORD	AT
	.WORD	BLKTBL
	.WORD	TWO
	.WORD	SUBB
	.WORD	GREAT
	.WORD	ZBRAN,$16	; Pop flag; if zero branch to $B25E (offset +22 from operand cell)
	.WORD	ERPSTO
	.WORD	PDOTQ	; Print counted inline text; resume after its payload
	.BYTE	11
	.BYTE	"RSTK EMPTY "
	.WORD	SPSTO
	.WORD	QUIT
	.WORD	ERP
	.WORD	AT
	.WORD	AT
	.WORD	SEMIS	; Return to caller thread

;	EIP+

; Dictionary: EIP+ [SYSTEM].
; Manual: One of a group of EMULATION words, used by the DEBUGGER. Not a user
; word.
LB266:
	.BYTE	$84,"EIP",$AB
	.WORD	LB22C	; LFA: previous name field in this vocabulary chain
EIPPL:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	TWO
	.WORD	EIP
	.WORD	PSTOR
	.WORD	SEMIS	; Return to caller thread

;	EBR

; Dictionary: EBR [SYSTEM].
; Implementation: Emulated BRANCH: fetch and display the displacement at EIP,
; then add it to EIP.
LB277:
	.BYTE	$83,"EB",$D2
	.WORD	LB266	; LFA: previous name field in this vocabulary chain
EBR:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	EIP
	.WORD	AT
	.WORD	AT
	.WORD	DUP
	.WORD	DOT
	.WORD	EIP
	.WORD	PSTOR
	.WORD	SEMIS	; Return to caller thread

EZBRAN:
	.WORD	DOCOL
	.WORD	ZBRAN,8	; Pop flag; if zero branch to $B29B (offset +8 from operand cell)
	.WORD	EIPPL
	.WORD	BRAN,4	; Jump to $B29D (offset +4 from operand cell)
	.WORD	EBR
	.WORD	SEMIS	; Return to caller thread

;	EI

; Dictionary: EI [SYSTEM].
; Manual: One of a group of EMULATION words, used by the DEBUGGER. Not a user
; word.
LB29F:
	.BYTE	$82,"E",$C9
	.WORD	LB277	; LFA: previous name field in this vocabulary chain
EI:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	ERP
	.WORD	AT
	.WORD	TWOP
	.WORD	AT
	.WORD	SEMIS	; Return to caller thread

ELIT:
	.WORD	DOCOL
	.WORD	EIP
	.WORD	AT
	.WORD	AT
	.WORD	EIPPL
	.WORD	SEMIS	; Return to caller thread

ECLIT:
	.WORD	DOCOL
	.WORD	EIP
	.WORD	AT
	.WORD	CAT
	.WORD	ONE
	.WORD	EIP
	.WORD	PSTOR
	.WORD	SEMIS	; Return to caller thread

LB2CC:
	.WORD	DOCOL
	.WORD	EIP
	.WORD	AT
	.WORD	COUNT
	.WORD	TDUP
	.WORD	PLUS
	.WORD	EIP
	.WORD	STORE
	.WORD	TDUP
	.WORD	TYPE
	.WORD	SEMIS	; Return to caller thread

EPDOTQ:
	.WORD	DOCOL
	.WORD	LB2CC
	.WORD	TDROP
	.WORD	SEMIS	; Return to caller thread

EPDO:
	.WORD	DOCOL
	.WORD	SWAP
	.WORD	ETOR
	.WORD	ETOR
	.WORD	SEMIS	; Return to caller thread

EPPLOO:
	.WORD	DOCOL
	.WORD	ERFROM
	.WORD	OVER
	.WORD	PLUS
	.WORD	ERFROM
	.WORD	TDUP
	.WORD	ETOR
	.WORD	ETOR
	.WORD	ROT
	.WORD	ZLESS
	.WORD	ZBRAN,6	; Pop flag; if zero branch to $B310 (offset +6 from operand cell)
	.WORD	SWAP
	.WORD	ONEP
	.WORD	LESS
	.WORD	ZBRAN,8	; Pop flag; if zero branch to $B31C (offset +8 from operand cell)
	.WORD	EBR
	.WORD	BRAN,$C	; Jump to $B326 (offset +12 from operand cell)
	.WORD	ERFROM
	.WORD	DROP
	.WORD	ERFROM
	.WORD	DROP
	.WORD	EIPPL
	.WORD	SEMIS	; Return to caller thread

EPLOOP:
	.WORD	DOCOL
	.WORD	ONE
	.WORD	EPPLOO
	.WORD	SEMIS	; Return to caller thread

ELEAV:
	.WORD	DOCOL
	.WORD	ERFROM
	.WORD	DROP
	.WORD	ERFROM
	.WORD	DROP
	.WORD	EI
	.WORD	ETOR
	.WORD	SEMIS	; Return to caller thread

ECOMP:
	.WORD	DOCOL
	.WORD	EIP
	.WORD	AT
	.WORD	AT
	.WORD	DUP
	.WORD	TWOP
	.WORD	NFA
	.WORD	IDDOT
	.WORD	COMMA
	.WORD	EIPPL
	.WORD	SEMIS	; Return to caller thread

; Forth tracer substitution table: count byte 16 followed by sixteen
; original-CFA / emulation-CFA pairs. CND uses these to emulate words that
; alter IP or the return stack. This is a Forth thread emulator, not a 6502
; CPU emulator.
LB356:
	.BYTE	16

	.WORD	BRAN
	.WORD	EBR

	.WORD	I
	.WORD	EI

	.WORD	R
	.WORD	EI

	.WORD	RPSTO
	.WORD	ERPSTO

	.WORD	TOR
	.WORD	ETOR

	.WORD	RFROM
	.WORD	ERFROM

	.WORD	COMP
	.WORD	ECOMP	; Inline CFA operand consumed by COMPILE

	.WORD	LEAVE
	.WORD	ELEAV

	.WORD	PLOOP
	.WORD	EPLOOP

	.WORD	PPLOO
	.WORD	EPPLOO

	.WORD	PDO
	.WORD	EPDO

	.WORD	PDOTQ	; Print counted inline text; resume after its payload
	.WORD	EPDOTQ

	.WORD	ALIT
	.WORD	LB2CC

	.WORD	CLIT	; Push following inline byte, zero-extended
	.WORD	ECLIT

	.WORD	LIT	; Push following inline 16-bit cell
	.WORD	ELIT	; Inline literal value, not a call

	.WORD	ZBRAN
	.WORD	EZBRAN

;	CND

; Dictionary: CND [SYSTEM].
; Manual stack: ( a1 --- a2 )
; Manual: This is an emulator primitive, which converts the address of a
; selected group of emulated words from their real code field address of the
; emulation word that is their equivalent. Not a user word.
LB397:
	.BYTE	$83,"CN",$C4
	.WORD	LB29F	; LFA: previous name field in this vocabulary chain
CND:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	LIT,LB356
	.WORD	COUNT
	.WORD	LIT,4
	.WORD	STAR
	.WORD	ZERO
	.WORD	PDO
	.WORD	TDUP
	.WORD	I
	.WORD	PLUS
	.WORD	AT
	.WORD	EQUAL
	.WORD	ZBRAN,$E	; Pop flag; if zero branch to $B3C9 (offset +14 from operand cell)
	.WORD	I
	.WORD	PLUS
	.WORD	TWOP
	.WORD	AT
	.WORD	SWAP
	.WORD	LEAVE
	.WORD	LIT,4
	.WORD	PPLOO,$FFE0	; Add stack increment; if continuing branch to $B3AF (offset -32 from operand cell)
	.WORD	DROP
	.WORD	SEMIS	; Return to caller thread

;	ERR

; Dictionary: ERR [SYSTEM].
; Manual stack: ( --- )
; Manual: This word prints the error message CODE DEFINITION, when TRACE or
; EMULATE are used on a CODE WORD. This prevents a crash, if an attempt was
; actually made to trace these words.
LB3D5:
	.BYTE	$83,"ER",$D2
	.WORD	LB397	; LFA: previous name field in this vocabulary chain
ERR:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	PDOTQ	; Print counted inline text; resume after its payload
	.BYTE	8
	.BYTE	"CODE DEF"
	.WORD	SEMIS	; Return to caller thread

;	'STEP

; Dictionary: 'STEP [SYSTEM].
; Manual stack: ( --- a1 )
; Manual: Returns the address of the execution variable used to control the
; STEP action. The word STEP gets vectored to an error message if you attempt
; to TRACE a code word. Normally, 'STEP contains the CFA of (STEP).
LB3EA:
	.BYTE	$85,$27,"STE",$D0
	.WORD	LB3D5	; LFA: previous name field in this vocabulary chain
TSTEP:
	.WORD	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.WORD	$D0	; User offset $00D0; initial address $0A10

;	'CONT

; Dictionary: 'CONT [SYSTEM].
; Manual stack: ( --- a1 )
; Manual: Returns the address of the execution variable used to control the
; CONT action. The word CONT gets vectored to an error message if you attempt
; to TRACE a code word. Normally, 'CONT contains the CFA of (CONT).
LB3F6:
	.BYTE	$85
	.BYTE	$27,"CON",$D4
	.WORD	LB3EA	; LFA: previous name field in this vocabulary chain
TCONT:
	.WORD	DOUSE	; CFA: user variable; push UP + unsigned offset byte
	.WORD	$D2	; User offset $00D2; initial address $0A12

;	(STEP)

; Dictionary: (STEP) [SYSTEM].
; Manual stack: ( --- )
; Manual: Performs a single step through the currently selected TRACE word.
; This is the function to which STEP is vectored, when a high level word is
; being traced. Not normally used by the user.
LB402:
	.BYTE	$86,"(STEP",$A9
	.WORD	LB3F6	; LFA: previous name field in this vocabulary chain
PSTEP:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	EIP
	.WORD	AT
	.WORD	AT
	.WORD	DUP
	.WORD	TWOP
	.WORD	NFA
	.WORD	IDDOT
	.WORD	DUP
	.WORD	LIT,SEMIS
	.WORD	SUBB
	.WORD	ZBRAN,$15	; Pop flag; if zero branch to $B43A (offset +21 from operand cell)
	.WORD	EIPPL
	.WORD	CND
	.WORD	EXEC
	.WORD	TAB
	.WORD	PDOTQ	; Print counted inline text; resume after its payload
	.BYTE	2
	.BYTE	">>"
	.WORD	DOTS
	.WORD	BRAN,$F	; Jump to $B447 (offset +15 from operand cell)
	.WORD	DROP
	.WORD	PDOTQ	; Print counted inline text; resume after its payload
	.BYTE	8
	.BYTE	"DEF END "
	.WORD	CR
	.WORD	SEMIS	; Return to caller thread

;	(CONT)

; Dictionary: (CONT) [SYSTEM].
; Manual stack: ( --- )
; Manual: Performs a continuous emulation through the currently selected
; TRACE word. This is the low level operation to which CONT gets vectored
; when a high level FORTH word is TRACED. This word is not normally used by
; the user at the keyboard.
LB44B:
	.BYTE	$86,"(CONT",$A9
	.WORD	LB402	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
PCONT:
	.WORD	CR
	.WORD	PSTEP
	.WORD	EIP
	.WORD	AT
	.WORD	AT
	.WORD	LIT,SEMIS
	.WORD	EQUAL
	.WORD	QTER
	.WORD	ORR
	.WORD	ZBRAN,$FFEC	; Pop flag; if zero branch to $B458 (offset -20 from operand cell)
	.WORD	SEMIS	; Return to caller thread

;	STEP

; Dictionary: STEP [FORTH].
; Manual stack: ( --- )
; Manual: Performs a TRACE single step, after a trace has been stopped, or a
; word has been selected for emulation with the EMULATE word.
LB470:
	.BYTE	$84,"STE",$D0
	.WORD	LB1AE	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	TSTEP
	.WORD	AT
	.WORD	EXEC
	.WORD	SEMIS	; Return to caller thread

;	CONT

; Dictionary: CONT [FORTH].
; Manual stack: ( --- )
; Manual: This is a vectored word which causes all of a definition to be
; traced after a trace has been interpreted, or an EMULATE command has been
; issued. As the trace scrolls up the screen, it can be interrupted at any
; time, by pressing any character key. To continue after interruption, simply
; enter CONT followed by a carriage return.
LB481:
	.BYTE	$84,"CON",$D4
	.WORD	LB470	; LFA: previous name field in this vocabulary chain
CONTT:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	TCONT
	.WORD	AT
	.WORD	EXEC
	.WORD	SEMIS	; Return to caller thread

;	EMULATE

; Dictionary: EMULATE [FORTH].
; Manual stack: ( --- t )
; Manual: Selects the word following EMULATE as the word to be traced by the
; select debugger. Revectors 'CONT and 'STEP to (CONT) and (STEP) if the word
; Is a high level word; otherwise vectors them to an error message routine.
; 125
LB492:
	.BYTE	$87,"EMULAT",$C5
	.WORD	LB481	; LFA: previous name field in this vocabulary chain
; Tracer engine: initialize EIP and emulated return-stack state, classify the
; next CFA with CND, and run either its special emulation handler or its
; normal behavior. STEP and CONT control advancement through these Forth
; tokens.
EMULAT:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	TICK
	.WORD	CFA
	.WORD	DUP
	.WORD	EIP
	.WORD	STORE
	.WORD	AT
	.WORD	LIT,HEX
	.WORD	AT
	.WORD	SUBB
	.WORD	ZBRAN,$27	; Pop flag; if zero branch to $B4DB (offset +39 from operand cell)
	.WORD	CR
	.WORD	PDOTQ	; Print counted inline text; resume after its payload
	.BYTE	12
	.BYTE	"CODE DEF !! "
	.WORD	LIT,ERR+2
	.WORD	CFA
	.WORD	DUP
	.WORD	TSTEP
	.WORD	STORE
	.WORD	TCONT
	.WORD	STORE
	.WORD	BRAN,$1A	; Jump to $B4F3 (offset +26 from operand cell)
	.WORD	EIPPL
	.WORD	ERPSTO
	.WORD	LIT,PSTEP+2
	.WORD	CFA
	.WORD	TSTEP
	.WORD	STORE
	.WORD	LIT,PCONT
	.WORD	CFA
	.WORD	TCONT
	.WORD	STORE
	.WORD	SEMIS	; Return to caller thread

;	TRACE

; Dictionary: TRACE [FORTH].
; Manual stack: ( --- t )
; Manual: Lists the lines of a definition of the word following TRACE.
; Performs the trace in the continuous mode, with vertical scrolling and
; stack output at each step.
LB4F5:
	.BYTE	$85,"TRAC",$C5
	.WORD	LB492	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	EMULAT
	.WORD	CONTT
	.WORD	SEMIS	; Return to caller thread

;	PICK

; Dictionary: PICK [FORTH].
; Manual stack: ( n1 --- n2 )
; Manual: Picks element n1 from the data stack and leaves it as value n2. One
; (1) PICK is equivalent to DUP, and two (2) PICK is equivalent to OVER, etc.
LB505:
	.BYTE	$84,"PIC",$CB
	.WORD	LB4F5	; LFA: previous name field in this vocabulary chain
PICK:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	TWO
	.WORD	STAR
	.WORD	SPAT
	.WORD	PLUS
	.WORD	AT
	.WORD	SEMIS	; Return to caller thread

LB51A:
	.WORD	DOCOL
	.WORD	THREE
	.WORD	PICK
	.WORD	EQUAL
	.WORD	ORR
	.WORD	SEMIS	; Return to caller thread

LB526:
	.WORD	DOCOL
	.WORD	DUP
	.WORD	AT
	.WORD	TWOP
	.WORD	ZERO
	.WORD	LIT,SEMIS+2
	.WORD	LB51A
	.WORD	LIT,PSCOD+2
	.WORD	LB51A
	.WORD	LIT,QUIT+2
	.WORD	LB51A
	.WORD	QTER
	.WORD	ORR
	.WORD	SWAP
	.WORD	DROP
	.WORD	ZEQU
	.WORD	SEMIS	; Return to caller thread

LB54E:
	.WORD	DOCOL
	.WORD	DUP
	.WORD	TWOP
	.WORD	SWAP
	.WORD	AT
	.WORD	TWOP
	.WORD	ZERO
	.WORD	LIT,COMP+2
	.WORD	LB51A
	.WORD	ZBRAN,$16	; Pop flag; if zero branch to $B57A (offset +22 from operand cell)
	.WORD	DROP
	.WORD	DUP
	.WORD	AT
	.WORD	TWOP
	.WORD	NFA
	.WORD	IDDOT
	.WORD	TWOP
	.WORD	SPACE
	.WORD	BRAN,$82	; Jump to $B5FA (offset +130 from operand cell)
	.WORD	ZERO
	.WORD	LIT,CLIT+2
	.WORD	LB51A
	.WORD	ZBRAN,$12	; Pop flag; if zero branch to $B596 (offset +18 from operand cell)
	.WORD	DROP
	.WORD	DUP
	.WORD	CAT
	.WORD	DOT
	.WORD	ONEP
	.WORD	SPACE
	.WORD	BRAN,$66	; Jump to $B5FA (offset +102 from operand cell)
	.WORD	ZERO
	.WORD	LIT,PDOTQ+2
	.WORD	LB51A
	.WORD	LIT,ALIT+2
	.WORD	LB51A
	.WORD	ZBRAN,$1E	; Pop flag; if zero branch to $B5C4 (offset +30 from operand cell)
	.WORD	DROP
	.WORD	DUP
	.WORD	COUNT
	.WORD	DUP
	.WORD	ROT
	.WORD	SWAP
	.WORD	TYPE
	.WORD	PLUS
	.WORD	ONEP
	.WORD	LIT,5
	.WORD	SPACS
	.WORD	BRAN,$38	; Jump to $B5FA (offset +56 from operand cell)
	.WORD	ZERO
	.WORD	LIT,LIT+2
	.WORD	LB51A
	.WORD	LIT,BRAN+2
	.WORD	LB51A
	.WORD	LIT,ZBRAN+2
	.WORD	LB51A
	.WORD	LIT,PPLOO+2
	.WORD	LB51A
	.WORD	LIT,PLOOP+2
	.WORD	LB51A
	.WORD	ZBRAN,$12	; Pop flag; if zero branch to $B5F8 (offset +18 from operand cell)
	.WORD	DROP
	.WORD	DUP
	.WORD	AT
	.WORD	DOT
	.WORD	SPACE
	.WORD	TWOP
	.WORD	BRAN,4	; Jump to $B5FA (offset +4 from operand cell)
	.WORD	DROP
	.WORD	SEMIS	; Return to caller thread

;	SOURCE

; Dictionary: SOURCE [FORTH].
; Manual stack: ( --- )
; Manual: Decompiles the word specified by the text following SOURCE, to its
; sequence of high level steps.
LB5FC:
	.BYTE	$86,"SOURC",$C5
	.WORD	LB505	; LFA: previous name field in this vocabulary chain
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	TICK
	.WORD	DUP
	.WORD	CFA
	.WORD	AT
	.WORD	LIT,HEX+2
	.WORD	CFA
	.WORD	AT
	.WORD	EQUAL
	.WORD	ZBRAN,$78	; Pop flag; if zero branch to $B693 (offset +120 from operand cell)
	.WORD	PDOTQ	; Print counted inline text; resume after its payload
	.BYTE	3
	.BYTE	" : "
	.WORD	DUP
	.WORD	NFA
	.WORD	IDDOT
	.WORD	SPACE
	.WORD	DUP
	.WORD	DUP
	.WORD	AT
	.WORD	TWOP
	.WORD	NFA
	.WORD	DUP
	.WORD	CAT
	.WORD	LIT,$40
	.WORD	ANDD
	.WORD	TWO
	.WORD	SPACS
	.WORD	ZBRAN,$F	; Pop flag; if zero branch to $B654 (offset +15 from operand cell)
	.WORD	PDOTQ	; Print counted inline text; resume after its payload
	.BYTE	10
	.BYTE	"[COMPILE] "
	.WORD	IDDOT
	.WORD	LB526
	.WORD	ZBRAN,$16	; Pop flag; if zero branch to $B670 (offset +22 from operand cell)
	.WORD	LB54E
	.WORD	OUT
	.WORD	AT
	.WORD	CSLL
	.WORD	GREAT
	.WORD	ZBRAN,4	; Pop flag; if zero branch to $B66C (offset +4 from operand cell)
	.WORD	CR
	.WORD	BRAN,$FFBF	; Jump to $B62D (offset -65 from operand cell)
	.WORD	DROP
	.WORD	DUP
	.WORD	NFA
	.WORD	AT
	.WORD	LIT,$40
	.WORD	ANDD
	.WORD	ZBRAN,$F	; Pop flag; if zero branch to $B68F (offset +15 from operand cell)
	.WORD	PDOTQ	; Print counted inline text; resume after its payload
	.BYTE	10
	.BYTE	"IMMEDIATE "
	.WORD	BRAN,4	; Jump to $B695 (offset +4 from operand cell)
	.WORD	ERR
	.WORD	DROP
	.WORD	CR
	.WORD	SEMIS	; Return to caller thread

;	MSREG

; ---------------------------------------------------------------------------
; SID SOUND SHADOW AND CONTROL WORDS
; ---------------------------------------------------------------------------
; Dictionary: MSREG [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- a1 )
; Manual: A system constant which returns the address of the memory area that
; is a copy of the SID chip sound register. This array is maintained to allow
; both reading and writing to the SID chip registers.
LB69B:
	.BYTE	$85,"MSRE",$C7
	.WORD	LB44B	; LFA: previous name field in this vocabulary chain
; SID software shadow at $779A. Most setters modify this RAM image because
; SID control registers cannot be read back normally. S! copies 32 bytes to
; SID hardware; setters alone do not necessarily change the sound
; immediately.
MSREG:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: SBASE [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- a1 )
; Manual: A system constant which returns the base address a1 of the SID
; chip.
LB6A7:
	.BYTE	$85,"SBAS",$C5
	.WORD	LB69B	; LFA: previous name field in this vocabulary chain
SBASE:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: CV [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- a1 )
; Manual: Returns the base address of the currently selected voice of the
; sound system.
LB6B3:
	.BYTE	$82,"C",$D6
	.WORD	LB6A7	; LFA: previous name field in this vocabulary chain
CV:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: WFORM [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual: A defining word used to create many of the sound control words. Not
; a user word. 151
LB6C4:
	.BYTE	$85,"WFOR",$CD
	.WORD	LB6B3	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: S! [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: A sound system primitive, which moves the contents of the memory
; copy of the SID chip, to the actual SID chip registers. This word must be
; executed whenever a change 141 is made to the SID chip registers. It is not
; done automatically, because there would then be a heavy speed penalty for
; each sound word executed. As a result, this word is used after a group of
; changes are performed to cause them to all have effect at once.
LB6F6:
	.BYTE	$82,"S",$A1
	.WORD	LB5FC	; LFA: previous name field in this vocabulary chain
SSTOR:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: SINIT [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: This is the sound initialization word. It must be executed before
; any other operations can be done to the sound system.
LB709:
	.BYTE	$85,"SINI",$D4
	.WORD	LB6F6	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: PWIDTH! [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Sets the PULSE width register value for voice #1, in the range 0 to
; 4095. See S!
LB725:
	.BYTE	$87,"PWIDTH",$A1
	.WORD	LB709	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: PWIDTH@ [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- n1 )
; Manual: Returns the PULSE width register value for voice #1, in the range 0
; to 4095. See S!
LB739:
	.BYTE	$87,"PWIDTH",$C0
	.WORD	LB725	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: FREQ! [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Sets the frequency value for the currently selected voice. This is
; the compliment of FREQ@. n1 is in the range 0 to 65,535. See S!
LB74D:
	.BYTE	$85,"FREQ",$A1
	.WORD	LB739	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: FREQ@ [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- n1 )
; Manual: Returns the frequency value from the currently selected voice. This
; is the compliment of FREQ! See S!
LB75D:
	.BYTE	$85,"FREQ",$C0
	.WORD	LB74D	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: TRIANGLE [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: Sets the currently selected voice to generate a triangle wave. This
; is one of several types of waveforms that can be generated. See also
; SQUARE, NOISE, SAWTOOTH. See S!
LB76D:
	.BYTE	$88,"TRIANGL",$C5
	.WORD	LB75D	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: GATE1 [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual: Enables the currently selected voice, that is, turns it ON. See S!
LB77F:
	.BYTE	$85,"GATE",$B1
	.WORD	LB76D	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: GATE0 [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: Disables the currently selected voice, that is, turns it OFF. See
; S!.
LB78E:
	.BYTE	$85,"GATE",$B0
	.WORD	LB77F	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: SAWTOOTH [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: Sets the current voice to generate a SAWTOOTH wave form. One of a
; group of four words, which select the basic waveform for a selected voice.
; See also NOISE, SQUARE, TRIANGLE. See S!
LB79D:
	.BYTE	$88,"SAWTOOT",$C8
	.WORD	LB78E	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: SYNC1 [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: When this word is executed, oscillator #1 will be hard synchronized
; with voice #3. See S!
LB7AF:
	.BYTE	$85,"SYNC",$B1
	.WORD	LB79D	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: SYNC0 [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: When this word is executed, oscillator #1 is not hard synchronized
; with voice #3, and each oscillator can be programmed independently. This is
; the normal condition. See S!
LB7BE:
	.BYTE	$85,"SYNC",$B0
	.WORD	LB7AF	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: SQUARE [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: Sets the currently selected voice to generate a square wave. This
; is one of several types of waveforms that can be generated. See also
; TRIANGLE, SAWTOOTH, and NOISE. See S1
LB7CD:
	.BYTE	$86,"SQUAR",$C5
	.WORD	LB7BE	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: RING1 [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Implementation: Enable ring modulation in the current voice shadow
; (control-register bit 2). S! commits it to hardware.
LB7DD:
	.BYTE	$85,"RING",$B1
	.WORD	LB7CD	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: RING0 [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Implementation: Disable ring modulation in the current voice shadow
; (control-register bit 2). S! commits it to hardware.
LB7EC:
	.BYTE	$85,"RING",$B0
	.WORD	LB7DD	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: NOISE [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: Sets the currently selected voice to generate noise. This is 136
; one of four basic signals the SID chip can generate. See also TRIANGLE,
; SAWTOOTH, SQUARE. See S!
LB7FB:
	.BYTE	$85,"NOIS",$C5
	.WORD	LB7EC	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: TEST1 [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: A sound control word, which can be used to synchronize oscillator
; #1 to external events. If this word is executed, oscillator #1 will stop
; output, until a TESTO is executed. Normally used for testing. See S!
LB80A:
	.BYTE	$85,"TEST",$B1
	.WORD	LB7FB	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: TEST0 [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: A sound control word, which can be used to synchronize oscillator
; #1 to external events. If this word is executed, oscillator #1 will be
; enabled-the normal condition. Normally used for testing. See S!
LB819:
	.BYTE	$85,"TEST",$B0
	.WORD	LB80A	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: VOICE1 [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: Sets the current voice to be manipulated by the sound control words
; to VOICE1, by setting the value of the CURVOICE system variable to the
; offset into the SID sound register area. See S!
LB828:
	.BYTE	$86,"VOICE",$B1
	.WORD	LB819	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: VOICE2 [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: Sets the current voice to be manipulated by the sound control words
; to VOICE2, by setting the value of the CURVOICE system variable to the
; offset into the SID sound register area. See S!
LB83B:
	.BYTE	$86,"VOICE",$B2
	.WORD	LB828	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: VOICE3 [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: Sets the current voice to be manipulated by the sound control words
; to VOICE3, by setting the value of the CURVOICE system variable to the
; offset into the SID sound register area. See S!
LB850:
	.BYTE	$86,"VOICE",$B3
	.WORD	LB83B	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: REGSET [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual: A low level primitive, used by the sound system. Not a user word.
LB865:
	.BYTE	$86,"REGSE",$D4
	.WORD	LB6C4	; LFA: previous name field in this vocabulary chain
REGSET:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: REGREAD [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual: A low level primitive, used by the sound system. Not a user word.
; 140
LB882:
	.BYTE	$87,"REGREA",$C4
	.WORD	LB865	; LFA: previous name field in this vocabulary chain
REGRED:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: ATTACK! [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Sets the attack register value for the currently selected voice, in
; the range 0 to 15. See S!
LB898:
	.BYTE	$87,"ATTACK",$A1
	.WORD	LB850	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: ATTACK@ [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- n1 )
; Manual: Returns the attack register value for the currently selected voice,
; in the range from 0 to 15. See S!
LB8BA:
	.BYTE	$87,"ATTACK",$C0
	.WORD	LB898	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: DECAY! [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Set the decay register value for the currently selected voice in
; the SID chip to value n1, in the range 0 to 15. See S!
LB8DA:
	.BYTE	$86,"DECAY",$A1
	.WORD	LB8BA	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: DECAY@ [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- n1 )
; Manual: Return the decay register value for the currently selected voice,
; in the range 0 to 15, See S!
LB8F5:
	.BYTE	$86,"DECAY",$C0
	.WORD	LB8DA	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: SUSTAIN! [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Sets the sustain register value for the currently selected voice.
; See S!
LB912:
	.BYTE	$88,"SUSTAIN",$A1
	.WORD	LB8F5	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: SUSTAIN@ [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- n1 )
; Manual: Returns the value of the sustain register for the currently
; selected voice. See S!
LB935:
	.BYTE	$88,"SUSTAIN",$C0
	.WORD	LB912	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: RELEASE! [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Sets the release register value for the currently selected voice.
; See S!
LB956:
	.BYTE	$88,"RELEASE",$A1
	.WORD	LB935	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: RELEASE@ [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- n1 )
; Manual: Reads the release register value for the currently selected voice.
; See S!
LB973:
	.BYTE	$88,"RELEASE",$C0
	.WORD	LB956	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: FILTER! [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Sets the filter center/cutoff frequency to the value specified as
; n1, in the range 0 to 2047. See S!
LB992:
	.BYTE	$87,"FILTER",$A1
	.WORD	LB973	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: RESONANCE! [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Sets the RESONANCE register value for the filter, lower values
; reduce filter effect, and higher values increase filter effect. N1 is in
; the range 0 to 15.
LB9B4:
	.BYTE	$8A,"RESONANCE",$A1
	.WORD	LB992	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: RESONANCE@ [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- n1 )
; Manual: Returns the current value of the filter, RESONANCE register
; setting, in the range 0 to 15.
LB9D9:
	.BYTE	$8A,"RESONANCE",$C0
	.WORD	LB9B4	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: FSELECT! [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Sets the filter select register, to cause the filter to be
; effective on the voices specified by the bits of value n1. The bit values
; for each voice are as follows: voice#1=01, voice#2=02, voice#3=04,
; external=08 Any or all of these values can be ORed together to create the
; value n1 passed to FSELECT! See S!.
LB9FC:
	.BYTE	$88,"FSELECT",$A1
	.WORD	LB9D9	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: FSELECT@ [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- n1 )
; Manual: Returns the filter select register, which holds the value n1 ---
; the voices specified to be filtered. The bit values for each voice are as
; follows: voice#l=01, voice#2=02, voice#3=04, external=08 These values can
; be 0Red together to create n1. See S!.
LBA19:
	.BYTE	$88,"FSELECT",$C0
	.WORD	LB9FC	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: FMODE! [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Sets the filter mode register value to select the type of filtering
; desired. Each of the low 4 bits of the value n1 are a type of filter action
; as follows: 128 low-pass=01, band-pass=02, high-pass=04 and voice #3 off=08
; Any of the first three filter types can be selected, or 0Red together, to
; form a more complex filter action. The last bit, VOICE #3 OFF, is used to
; remove voice #3 from the output without turning it off internally. This
; allows oscillator #3 to be used to modulate the other voices, without its
; output appearing directly in the output of the sound chip. See S!
LBA38:
	.BYTE	$86,"FMODE",$A1
	.WORD	LBA19	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: FMODE@ [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- n1 )
; Manual: Returns the filter mode register value, indicating the type of
; filter currently selected. See FMODE! for further information about the
; value returned as n1. See S!
LBA59:
	.BYTE	$86,"FMODE",$C0
	.WORD	LBA38	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: VOLUME! [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Sets the current value of the volume register to value n1 in the
; range 0 to 15 in the SID sound generator chip. See S!
LBA78:
	.BYTE	$87,"VOLUME",$A1
	.WORD	LBA59	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: VOLUME@ [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- n1 )
; Manual: Fetches the current value of the volume register in the SID sound
; generator chip. See S!
LBA94:
	.BYTE	$87,"VOLUME",$C0
	.WORD	LBA78	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: OSC3@ [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- n1 )
; Manual: Returns the output of the waveform for oscillator #3 as a number n1
; in the range 0 to 255.
LBAB2:
	.BYTE	$85,"OSC3",$C0
	.WORD	LBA94	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: ENV3@ [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- n1 )
; Manual: Returns the value of the oscillator #3 ENVELOPE generator, in the
; range 0 to 255.
LBAC4:
	.BYTE	$85,"ENV3",$C0
	.WORD	LBAB2	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: SPOBJ [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- a1 )
; Manual: This is a system variable used In the creation of a sprite data
; definition, after a sprite edit has been completed. Not a user word.
LBAD6:
	.BYTE	$85,"SPOB",$CA
	.WORD	LB882	; LFA: previous name field in this vocabulary chain
SPOBJ:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: SPINDX [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- a1 )
; Manual: This is a system variable used in the creation of a sprite data
; definition after a sprite edit has been completed. Not a user word.
LBAE2:
	.BYTE	$86,"SPIND",$D8
	.WORD	LBAD6	; LFA: previous name field in this vocabulary chain
SPINDX:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: SPBYT [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- a1 )
; Manual: This is a system variable used in the creation of a sprite data
; definition after a sprite edit has been completed. Not a user word.
LBAEF:
	.BYTE	$85,"SPBY",$D4
	.WORD	LBAE2	; LFA: previous name field in this vocabulary chain
SPBYT:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: SCPTR [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- a1 )
; Manual: A system variable, used in the creation of a sprite definition. Not
; a user word.
LBAFB:
	.BYTE	$85,"SCPT",$D2
	.WORD	LBAEF	; LFA: previous name field in this vocabulary chain
SCPTR:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: SPBIT [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: A system sprite word used to read bytes from the screen in the
; process of building a sprite data definition. Not a user word.
LBB07:
	.BYTE	$85,"SPBI",$D4
	.WORD	LBAFB	; LFA: previous name field in this vocabulary chain
; Sprite conversion worker: use SPOBJ/SPINDX/SPBYT/SCPTR user variables to
; accumulate bitmap data. Sprite storage has three bytes per row and 21 rows
; (63 payload bytes per 64-byte sprite slot).
SPBIT:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: SPGET [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: A system sprite word used to read bytes from the screen in the
; process of building a sprite data definition. Not a user word.
LBB4F:
	.BYTE	$85,"SPGE",$D4
	.WORD	LBB07	; LFA: previous name field in this vocabulary chain
SPGET:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: SPRITE [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: Builds the sprite data definition from the characters on the 144
; screen In the sprite definition area within the sprite editor border. This
; word is automatically executed by the sprite editor when the <RETURN> key
; is pressed upon completion of a sprite edit.
LBB85:
	.BYTE	$86,"SPRIT",$C5
	.WORD	LBB4F	; LFA: previous name field in this vocabulary chain
SPRITE:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: MASK [SYSTEM].
; Manual stack: ( --- a1 )
; Manual: An array, which contains the values used when converting from bit
; number to the mask value for that bit, used by ORMASK and ANDMASK. This
; array contains 8 values ranging from 01 to 80, as follows: 01, 02, 04, 08,
; 10, 20, 40, 80.
LBBB4:
	.BYTE	$84,"MAS",$CB
	.WORD	LBB85	; LFA: previous name field in this vocabulary chain
MASK:
	.WORD	DOVAR	; CFA: variable; push the parameter-field address
	.BYTE	$01,$02,$04,$08
	.BYTE	$10,$20,$40,$80

;	ORMASK

; Dictionary: ORMASK [SYSTEM].
; Manual stack: ( n1/a1 --- )
; Manual: Sets the bit specified by bit number n1 in the byte contained in
; address a1. Example: "4 500 ORMASK" OR the contents of address 500 with
; 00010000 binary, and replace the result in address 500. Used to manipulate
; the bits of the various sprite registers.
LBBC5:
	.BYTE	$86,"ORMAS",$CB
	.WORD	LBBB4	; LFA: previous name field in this vocabulary chain
ORMASK:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	SWAP
	.WORD	MASK
	.WORD	PLUS
	.WORD	CAT
	.WORD	OVER
	.WORD	CAT
	.WORD	ORR
	.WORD	SWAP
	.WORD	CSTOR
	.WORD	SEMIS	; Return to caller thread

;	ANDMASK

; Dictionary: ANDMASK [SYSTEM].
; Manual stack: ( n1/a1 --- )
; Manual: This is a SPRITE system primitive, which takes a bit number n1 in
; the range 0 to 7, and clears that bit in the byte contained at address a1.
; Example "4 500 ANDMASK" resets sprite register bit 4 and the value in
; address 500 with 1110 1111 binary, and stores the value back in location
; 500. This word is useful for manipulating the various sprite register bits.
LBBE4:
	.BYTE	$87,"ANDMAS",$CB
	.WORD	LBBC5	; LFA: previous name field in this vocabulary chain
ANDMSK:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	SWAP
	.WORD	MASK
	.WORD	PLUS
	.WORD	CAT
	.WORD	LIT,$FF
	.WORD	XORR
	.WORD	OVER
	.WORD	CAT
	.WORD	ANDD
	.WORD	SWAP
	.WORD	CSTOR
	.WORD	SEMIS	; Return to caller thread

;	MASK?

; Dictionary: MASK? [SYSTEM].
; Manual stack: ( n1/a1/f1 --- )
; Manual: This word allows you to specify a boolean flag to select which of
; the operations "ORMASK" and "ANDMASK" are done. If f1 is zero (0), an
; "ANDMASK" is performed. And if fl is non-zero, an "ORMASK" is done. The
; additional parameters n1 and a1, are passed on to the appropriate function.
; Used by the XPAND word in determining the expansion of a particular sprite.
LBC0A:
	.BYTE	$85,"MASK",$BF
	.WORD	LBBE4	; LFA: previous name field in this vocabulary chain
MASKQ:
	.WORD	DOCOL	; CFA: colon definition; parameter field is a Forth thread
	.WORD	ZBRAN,8	; Pop flag; if zero branch to $BC1E (offset +8 from operand cell)
	.WORD	ORMASK
	.WORD	BRAN,4	; Jump to $BC20 (offset +4 from operand cell)
	.WORD	ANDMSK
	.WORD	SEMIS	; Return to caller thread

;	COLOR

; Dictionary: COLOR [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1/n2 --- )
; Manual: Sets the color n1 for sprite number n2. The color numbers are the
; same as shown on page 139 of the Commodore 64 Users Manual. 117
LBC22:
	.BYTE	$85,"COLO",$D2
	.WORD	LBAC4	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: SHOW [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Turns on the sprite specified by n1 and makes it visible on the
; screen. N1 is in the range 0 to 7.
LBC36:
	.BYTE	$84,"SHO",$D7
	.WORD	LBC22	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: HIDE [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Causes the sprite specified by n1 to be hidden from the screen
; view. See also SHOW.
LBC47:
	.BYTE	$84,"HID",$C5
	.WORD	LBC36	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: XY [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1/n2/n3 --- )
; Manual: Moves sprite n3 to screen position x=n1 and y=n2. This is the fast
; version which only has access to the first 255 X locations on the screen.
; Before XY can be used, the word CXY must have been used at least once to
; initialize the most significant bit of the sprite position. n1 is in the
; range 0 to 255, and n2 is in the range 0 to 159. n3 is the sprite number
; and must be in the range 0 to 7.
LBC58:
	.BYTE	$82,"X",$D9
	.WORD	LBC47	; LFA: previous name field in this vocabulary chain
XY:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: CXY [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1/n2/n3 --- )
; Manual: This is the sprite position control word, which allows any sprite
; n3 to be placed at any address on the screen at n1=x and n2=y. This slower
; version of XY allows full screen placement of a sprite. See XY.
LBC77:
	.BYTE	$83,"CX",$D9
	.WORD	LBC58	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: MULTI [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Selects multi-color mode for sprite n1. Don't forget to set MCLR1
; and MCLR2 first.
LBCC1:
	.BYTE	$85,"MULT",$C9
	.WORD	LBC77	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: HIRES [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Causes the sprite specified by n1 to be set in high resolution
; mode. This is the default mode, where each sprite has a foreground and a
; background color. See also MULTI, for use of the multi-color sprite mode.
; Pronounced "hi rez."
LBCD3:
	.BYTE	$85,"HIRE",$D3
	.WORD	LBCC1	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: XPAND [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( f1/f2/n1 --- )
; Manual: A sprite control word, which allows sprite n1 to be expanded in
; either vertical or horizontal directions, or both. The boolean flag f1 is
; the X direction expand flag, and flag f2 is the Y direction expand flag.
; Example "1 0 3 XPAND" will expand sprite 3 in the X direction, but not the
; Y direction.
LBCE5:
	.BYTE	$85,"XPAN",$C4
	.WORD	LBCD3	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: MCLR1 [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Implementation: ( color -- ) Set the VIC-II shared sprite multicolor-1
; register.
LBD05:
	.BYTE	$85,"MCLR",$B1
	.WORD	LBCE5	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: MCLR2 [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Implementation: ( color -- ) Set the VIC-II shared sprite multicolor-2
; register.
LBD17:
	.BYTE	$85,"MCLR",$B2
	.WORD	LBD05	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: SB [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Stack (from code): ( -- block-number )
; Original C64 manual: A system constant, #30 hex in this system, which specifies the 64
; byte block where the sprite data definitions start; $40 hex=64 decimal, and
; $30 times $40 is $0C00, the start of the sprite definition area.
LBD29:
	.BYTE	$82,"S",$C2
	.WORD	LBC0A	; LFA: previous name field in this vocabulary chain
SB:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: SBLK [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- a1 )
; Manual: This is a system constant which returns the address a1 of an array
; which contains the sprite data block pointer bytes. This array is located
; at $07F8, just beyond the end of the display screen.
LBD32:
	.BYTE	$84,"SBL",$CB
	.WORD	LBD29	; LFA: previous name field in this vocabulary chain
SBLK:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: SPBASE [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: Initializes the array SBLK to contain the proper pointers to the
; sprite data definition areas. Automatically executed when a new sprite is
; defined, or when a sprite is read from mass storage.
LBD3D:
	.BYTE	$86,"SPBAS",$C5
	.WORD	LBD32	; LFA: previous name field in this vocabulary chain
; Initialize the eight default-screen sprite pointers at $07F8 to consecutive
; 64-byte sprite blocks beginning at SB. These pointers depend on the VIC
; screen/bank configuration.
SPBASE:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: CUR [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1/n2 --- )
; Manual: This is another sprite system primitive, but one which might be
; useful to some people. It allows you to specify the location on the screen
; where the cursor will be 119 positioned, by performing the system call
; which positions the cursor. The parameters are n1 = the X position, and n2
; = the Y position for the new cursor location.
LBD64:
	.BYTE	$83,"CU",$D2
	.WORD	LBD3D	; LFA: previous name field in this vocabulary chain
CUR:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: VDG [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: A system sprite editor primitive used to draw a vertical line on
; the screen at column n1. Not a user word.
LBD80:
	.BYTE	$83,"VD",$C7
	.WORD	LBD64	; LFA: previous name field in this vocabulary chain
VDG:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: BDG [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: This is another system sprite primitive. It draws a horizontal line
; on the screen as a line specified by n1, 26 characters long, to make the
; top and bottom of the borders of the sprite editor. This is not a user
; word.
LBDA4:
	.BYTE	$83,"BD",$C7
	.WORD	LBD80	; LFA: previous name field in this vocabulary chain
BDG:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: -SPOBJ [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- n1/a1 )
; Manual: Converts the sprite number n1 to the address a1 of the data
; definition area for that sprite. Also leaves a copy of the sprite number on
; the stack as n1. This is a low level sprite manipulation word, normally
; used only by the system.
LBDC8:
	.BYTE	$86,"-SPOB",$CA
	.WORD	LBDA4	; LFA: previous name field in this vocabulary chain
DSPOBJ:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: RBYT [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( --- )
; Manual: A system primitive, used to read a byte of the sprite currently
; selected and about to be edited. A "*" is shown on the screen for each bit
; of the byte read, which was non zero. Probably not a useful user word.
LBDEB:
	.BYTE	$84,"RBY",$D4
	.WORD	LBDC8	; LFA: previous name field in this vocabulary chain
RBYT:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: SPEDIT [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Enters the sprite edit mode with sprite n1. Shows the current form
; of the selected sprite. SPEDIT is terminated by pressing <RETURN>.
LBE4A:
	.BYTE	$86,"SPEDI",$D4
	.WORD	LBD17	; LFA: previous name field in this vocabulary chain
; Interactive sprite editor: display the editing guide, initialize
; sprite/cursor state and key-repeat behavior, process 21 rows of three
; bytes, then wait for RETURN and rebuild the sprite data.
SPEDIT:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: NEWSPRITE [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Enters the sprite editor, with sprite n1 cleared. You now use the
; cursor movement keys and the star (*) symbol to draw your sprite on the
; screen within the box shown. Pairs of symbols in the form "**", "_*", "*_"
; or "__" are used to select the specific color in multi-color mode.
LBEFE:
	.BYTE	$89,"NEWSPRIT",$C5
	.WORD	LBE4A	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: SCRN? [SYSTEM].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- n2 )
; Manual: A system primitive, which converts the sprite number n1 to the mass
; storage screen which contains, or will contain, the data statements for
; that sprite. Each sprite is assigned a particular location on a mass
; storage screen. Eight (8) sprites can be stored in two screens. Sprites 0
; to 3 are always located in screen one (1), and sprites 4 through 7 are
; always located in screen two (2). Each sprite is 142 assigned four (4)
; lines of its first screen to hold the ASCII decimal values associated with
; that sprite. Sprite 0 is located on line 0 through 3 of screen 1, sprite 1
; is located on fines 4 through 7 of screen 1, and so on. See also SPWRITE
; and SPREAD.
LBF1A:
	.BYTE	$85,"SCRN",$BF
	.WORD	LBDEB	; LFA: previous name field in this vocabulary chain
; Split a sprite index (clamped to at most 7) using /MOD by four: return the
; slot within a screen and screen number 1 or 2. SPWRITE/SPREAD use 256 text
; bytes per serialized sprite.
SCRNQ:
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: SPWRITE [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Writes sprite n1 out of the FORTH screen, either screen 1 or 2,
; from the sprite data area where it may be written to or read from. Sprites
; 0 to 3 are on screen 1, and sprites 4 through 7 are on screen 2. Each
; sprite has four lines, and its data is maintained in ASCII decimal in the
; screen. See SPREAD.
LBF34:
	.BYTE	$87,"SPWRIT",$C5
	.WORD	LBEFE	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
; Dictionary: SPREAD [FORTH].
; IMNOTWOPR: unavailable; reports NO C64 and returns to the serial prompt.
; Original C64 manual stack: ( n1 --- )
; Manual: Reads sprite n1 from the FORTH screen 1 or 2, into the sprite data
; area for the sprite specified. Each sprite has a designated area where it
; may be written to or read from. Sprites 0 to 3 are on screen 1, and sprites
; 4 through 7 are on screen 2. Each sprite has four lines, and its data is
; maintained in ASCII decimal in the screen. See SPWRITE.
LBFA0:
	.BYTE	$86,"SPREA",$C4
	.WORD	LBF34	; LFA: previous name field in this vocabulary chain
	.WORD	NO_C64	; CFA: unsupported C64 word; report NO C64

; ---------------------------------------------------------------------------
.include "forth_words.inc"

.segment "VECTORS"
	.word	shell_nmi		; NMI vector address
	.word	reset		; RESET vector address
	.word	shell_irq		; IRQ/BRK vector address
