; REALIO=6: IMNOTWOPR, with the same board map as src/ferrous/forth.cfg.
; This file is included after the historical platform options, before macros.
ROMSW  .set 1
RORSW  .set 1
KIMROM .set 0
DISKO  .set 0
EXTIO  .set 0
TIME   .set 0
NULCMD .set 0
GETCMD .set 1
ROMLOC .set $C000
RAMLOC .set $0600
BUFPAG .set 2
BUF    .set $0204           ; Four pre-buffer bytes are kept off the CPU stack.
BUFLEN .set 80             ; 79 input characters; fits the signed line-copy loop.
LINLEN .set 80
STKEND .set 511

WOPR_RAM_END = $B000        ; Exclusive end of RAM; VIA starts here.
WOPR_ACIA = $B010
OUTCH = WOPR_PUTC
CZGETL = WOPR_TRY_GETC
