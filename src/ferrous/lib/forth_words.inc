; Small additions to the serial shell's FORTH vocabulary.
; Dictionary: THEN [FORTH]; immediate.
THEN_NFA:
    .byte $C4,"THE",$CE
    .word LBFA0
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

; Dictionary: WORDS [FORTH].
WORDS_NFA:
    .byte $85,"WORD",$D3
    .word RECURSE_NFA
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
