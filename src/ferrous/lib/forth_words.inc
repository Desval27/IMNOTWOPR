; Small additions to the serial shell's FORTH vocabulary.
; Dictionary: THEN [FORTH]; immediate.
THEN_NFA:
    .byte $C4,"THE",$CE
    .word SOURCE_NFA          ; Previous FORTH word; bypass removed SID/sprite words
    .word DOCOL
    .word ENDIF,SEMIS

; Dictionary: NEGATE [FORTH].
NEGATE_NFA:
    .byte $86,"NEGAT",$C5
    .word THEN_NFA
    .word DOCOL
    .word MINUS,SEMIS

; Dictionary: RECURSE [FORTH]; immediate.
RECURSE_NFA:
    .byte $C7,"RECURS",$C5
    .word NEGATE_NFA
    .word DOCOL
    .word QCOMP,LATES,PFA,CFA,COMMA,SEMIS

; Dictionary: CLEAR [FORTH].
; Stack: ( -- )
CLEAR_NFA:
    .byte $85,"CLEA",$D2
    .word RECURSE_NFA
CLEAR:
    .word DOCOL
    .word PDOTQ
    .byte clear_text_end-clear_text
clear_text:
    .byte $1B,"[2J"       ; ESC [ 2 J: erase entire screen
    .byte $1B,"[H"        ; ESC [ H: move cursor home
clear_text_end:
    .word SEMIS

; Dictionary: RESET [FORTH].
; Stack: ( -- )
RESET_NFA:
    .byte $85,"RESE",$D4
    .word CLEAR_NFA
RESET:
    .word DOCOL
    .word PDOTQ
    .byte reset_text_end-reset_text
reset_text:
    .byte $1B,"[C"       ; ESC [ C: reset terminal to initial state
reset_text_end:
    .word SEMIS


; Dictionary: .COORD [FORTH].
; Stack: ( u -- )
; Print unsigned digits in the current BASE, without spaces.
DOTCOORD_NFA:
    .byte $86,".COOR",$C4         ; .COORD, final D has bit 7 set
    .word RESET_NFA
DOTCOORD:
    .word DOCOL
    .word ZERO                  ; Supply high cell of double number
    .word BDIGS                 ; <#
    .word DIGS                  ; #S
    .word EDIGS                 ; #>
    .word TYPE
    .word SEMIS

; Dictionary: AT-XY [FORTH].
; Stack: ( x y -- )
; Zero-based column and row; emit ESC[row;columnH.
ATXY_NFA:
    .byte $85,"AT-X",$D9         ; AT-XY, final Y has bit 7 set
    .word DOTCOORD_NFA
ATXY:
    .word DOCOL

    .word BASE,AT,TOR           ; BASE @ >R: save caller's base
    .word DECIM                 ; DECIMAL

    .word PDOTQ
    .byte 2
    .byte $1B,"["               ; ESC [

    .word ONEP,DOTCOORD         ; Print y+1; leaves x

    .word CLIT
    .byte ";"                   
    .word EMIT

    .word ONEP,DOTCOORD         ; Print x+1; consumes x

    .word CLIT
    .byte "H"
    .word EMIT

    .word RFROM,BASE,STORE      ; R> BASE !: restore caller's base
    .word SEMIS    

; Dictionary: VER [FORTH].
; Stack: ( -- )
VER_NFA:
    .byte $83,"VE",$D2
    .word ATXY_NFA
    .word DOCOL
    .word PDOTQ
    .byte ver_end-ver_text
ver_text:
    .byte "WHOPPING FORTH VERSION 0.1",13,10
ver_end:
    .word SEMIS

; Dictionary: WORDS [FORTH].
WORDS_NFA:
    .byte $85,"WORD",$D3
    .word VER_NFA
    .word DOCOL
    .word VLIST,SEMIS

; Dictionary: HELP [FORTH].
HELP_NFA:
    .byte $84,"HEL",$D0
    .word WORDS_NFA
    .word DOCOL
    .word PDOTQ
    .byte help_end-help_text
help_text:
    .byte "2 3 + .    : DOUBLE 2 * ;    7 DOUBLE .",13,10
    .byte "0 VARIABLE N    42 N !    N @ .",13,10
    .byte ".S WORDS HEX DECIMAL  |  Ctrl-C/ABORT recover; COLD clears definitions.",13,10
    .byte "C64 devices report NO C64. BYE returns to Joshua's monitor.",13,10
help_end:
    .word SEMIS

; Dictionary: BYE [FORTH].
BYE_NFA:
    .byte $83,"BY",$C5
    .word HELP_NFA
    .word *+2
    .byte $DB                ; W65C02 STP; ca65's generic 65C02 mode omits it.

FORTH_BUILTIN_LATEST = BYE_NFA
