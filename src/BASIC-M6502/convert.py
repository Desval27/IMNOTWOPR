#!/usr/bin/env python3
"""Translate this 1978 BASIC listing, not arbitrary MACRO-10 programs.

Angle brackets delimit both blocks and expressions. Parse them before translating
instructions, and never interpret punctuation inside strings or comments.
"""
import argparse
from pathlib import Path
import re

OPCODES = set("ADC AND ASL BCC BCS BEQ BIT BMI BNE BPL BRK BVC BVS CLC CLD CLI CLV CMP CPX CPY DEC DEX DEY EOR INC INX INY JMP JSR LDA LDX LDY LSR NOP ORA PHA PHP PLA PLP ROL ROR RTI RTS SBC SEC SED SEI STA STX STY TAX TAY TSX TXA TXS TYA".split())
MACROS = set("ACRLF SYNCHK DT LDWD LDWDI LDWX LDWXI LDXY LDXYI STWD STWX STXY CLR COM PULWD PSHWD JEQ JNE BCCA BCSA BEQA BNEA BMIA BPLA BVCA BVSA INCW SKIP1 SKIP2 DCI DCE DC BASIC_ROR".split())
HEADER = '''; BASIC M6502 8K VER 1.1 BY MICRO-SOFT
; Generated from ms_basic_1978.asm by convert.py. See BUILDING.md.
.setcpu "6502"
.segment "LOWRAM"
.org 0

; DC marks the final character; DT does not add a terminator.
.macro DC text
    .repeat .strlen(text) - 1, char_index
        .byte .strat(text, char_index)
    .endrepeat
    .byte .strat(text, .strlen(text) - 1) | $80
.endmacro
'''


def split_comment(line):
    quoted = False
    for i, char in enumerate(line):
        if char == '"':
            quoted = not quoted
        elif char == ';' and not quoted:
            return line[:i], line[i:]
    return line, ""


class Converter:
    def __init__(self):
        self.output = [HEADER.rstrip()]
        self.blocks = []
        self.radix = 10
        self.in_macro = None
        self.configuration = True
        self.ror_wrapper = False
        self.macros = set(MACROS)
        self.line = 0

    def emit(self, text):
        self.output.append(text)

    def expr(self, text):
        # Keep string contents intact; character constants are numeric expressions.
        tokens = re.findall(r'"[^"\n]*"|\^[OD][0-9]+|[A-Za-z_$%@][A-Za-z0-9_$%@.]*|[0-9]+\.?|.', text, re.I)
        result = []
        for token in tokens:
            if not token.startswith('"'):
                token = token.upper()
            if token.startswith('"'):
                if len(token) != 3:
                    raise ValueError(f"line {self.line}: non-character expression {token}")
                token = str(ord(token[1]))
            elif token.startswith(('^O', '^D')):
                token = str(int(token[2:], 8 if token[1] == 'O' else 10))
            elif token[0].isdigit():
                # MACRO-10 accepts 8 and 9 as digits even in radix 8.
                base = 10 if token.endswith('.') else self.radix
                value = 0
                for digit in token.rstrip('.'):
                    value = value * base + int(digit)
                token = str(value)
            elif token == 'RESTORE':
                # MACRO-10 identifies symbols by their first six characters.
                token = 'RESTOR'
            elif token == '$Z':
                token = 'SIMBASE'
            elif token == '%Q':
                token = 'macro_done' if self.in_macro else '@Q'
            elif token == '.':
                token = '*'
            elif token == '<':
                token = '('
            elif token == '>':
                token = ')'
            elif token == '!':
                token = '|'
            if self.in_macro in ('DCI', 'DCE') and token == ('A' if self.in_macro == 'DCI' else 'X'):
                token = 'text'
            result.append(token)
        return ''.join(result).strip()

    def statement(self, code):
        code = code.strip()
        if not code:
            return
        label = re.match(r'^([\w$%]+):+!?', code)
        if label:
            self.emit(self.expr(label[1]) + ':')
            code = code[label.end():].strip()
            if not code:
                return
        assignment = re.match(r'^(\w+)\s*==?\s*(.*)$', code)
        if assignment:
            name, value = assignment.groups()
            # Configuration and token/error counters are reassigned by the source.
            operator = '.set' if self.configuration or name.upper() in ('Q', 'BUFOFS') else '='
            self.emit(f'{name.upper()} {operator} {self.expr(value)}')
            return
        match = re.match(r'([A-Za-z.][A-Za-z0-9.]*)\s*(.*)', code)
        if not match:
            self.emit('    .byte ' + self.expr(code))
            return
        op, arg = match[1].upper(), match[2].strip()
        if op in ('TITLE', 'SEARCH', 'SALL', 'PAGE', 'XLIST', 'LIST', '.XCREF', '.CREF', 'PURGE', 'END'):
            return
        if op == 'SUBTTL':
            self.emit('; ' + arg)
        elif op == 'RADIX':
            self.radix = int(arg)
        elif op == 'PRINTX':
            self.emit('; Original assembly notice: ' + arg)
        elif op == 'ORG':
            if arg.upper() == 'ROMLOC':
                self.emit('.segment "BASIC"')
                self.emit('.org ROMLOC')
                self.emit('.assert * = $0800, error, "Linker layout requires the original Apple configuration"')
            else:
                # .org alone changes addresses but does not emit the intervening gap.
                self.emit('    .res (' + self.expr(arg) + ') - *, 0')
        elif op == 'BLOCK':
            self.emit('    .res ' + self.expr(arg) + ', 0')
        elif op == 'EXP':
            self.emit('    .byte ' + self.expr(arg))
        elif op == 'XWD':
            marker, value = arg.split(',')
            if self.expr(marker) != '512':
                raise ValueError(f"line {self.line}: unknown cross-assembler XWD tag")
            self.emit('    .byte ' + self.expr(value))
        elif op == 'ADR':
            self.emit('    .word ' + self.expr(arg))
        elif op in ('DT', 'DC', 'DCI', 'DCE'):
            if arg.startswith('(') and arg.endswith(')'):
                arg = arg[1:-1]
            self.emit('    ' + op + ' ' + (arg if arg.startswith('"') else self.expr(arg)))
        elif op in OPCODES:
            arg = arg.rstrip(',')
            if op == 'ROR':
                self.emit('    BASIC_ROR {' + self.expr(arg) + '}')
            else:
                operand = self.expr(arg)
                if operand.startswith('('):
                    # Expression grouping must not select indirect addressing.
                    operand = '0+' + operand
                self.emit('    ' + op.lower() + (' ' + operand if arg else ''))
        elif op.endswith('I') and op[:-1] in OPCODES:
            self.emit('    ' + op[:-1].lower() + ' #.lobyte(' + self.expr(arg) + ')')
        elif op.endswith('DY') and op[:-2] in OPCODES:
            self.emit('    ' + op[:-2].lower() + ' (' + self.expr(arg) + '),y')
        elif op == 'JMPD':
            self.emit('    jmp (' + self.expr(arg) + ')')
        elif op in self.macros:
            self.emit('    ' + op + (' ' + self.expr(arg) if arg else ''))
        elif op in ('HRRZ', 'HRLI', 'JRST', 'OUTCHR', 'INCHWL', 'TJSR'):
            self.emit('    .error "PDP-10 simulator instruction is not supported"')
        elif not arg:
            self.emit('    .byte ' + self.expr(code))
        else:
            raise ValueError(f"line {self.line}: unsupported statement {code!r}")

    def parse(self, code):
        code = code.strip()
        # Labels can precede conditionals as well as instructions.
        label = re.match(r'^([\w$%]+):+!?', code)
        if label:
            self.emit(self.expr(label[1]) + ':')
            code = code[label.end():].strip()
        block = re.match(r'^(IFNDEF|IFDEF|IFE|IFN|IF1|IF2|REPEAT|DEFINE)\b(.*?),\s*<', code, re.I)
        if block:
            kind, arg = block[1].upper(), block[2].strip()
            if kind == 'IFE' and arg.upper() == 'RORSW' and not self.ror_wrapper:
                # ca65 cannot redefine an instruction mnemonic.
                self.emit('.if RORSW\n.macro BASIC_ROR operand\n    ror operand\n.endmacro\n.endif')
                self.ror_wrapper = True
            closing = '.endif'
            if kind == 'DEFINE':
                self.configuration = False
                macro = re.fullmatch(r'(\w+)\s*(?:\((\w+)\))?', arg)
                if not macro:
                    raise ValueError(f"line {self.line}: bad macro {arg}")
                name, param = macro.groups()
                self.macros.add(name.upper())
                self.in_macro = name.upper()
                if name.upper() == 'ROR':
                    name = 'BASIC_ROR'
                if name.upper() in ('DCI', 'DCE'):
                    param = 'text'
                self.emit('.macro ' + name + (' ' + param if param else ''))
                if name.upper() == 'INCW':
                    self.emit('    .local macro_done')
                closing = '.endmacro'
            elif kind == 'REPEAT':
                self.emit('.repeat ' + self.expr(arg))
                closing = '.endrepeat'
            elif kind in ('IF1', 'IF2'):
                self.emit('.if ' + ('0' if kind == 'IF1' else '1'))
            elif kind in ('IFDEF', 'IFNDEF'):
                self.emit('.' + kind.lower() + ' ' + self.expr(arg))
            else:
                self.emit('.if (' + self.expr(arg) + ') ' + ('=' if kind == 'IFE' else '<>') + ' 0')
            self.blocks.append((closing, self.line))
            self.parse(code[block.end():])
            return
        # Only a > outside an expression and outside a string closes a block.
        depth, quoted = 0, False
        for i, char in enumerate(code):
            if char == '"':
                quoted = not quoted
            elif not quoted:
                if char == '<':
                    depth += 1
                elif char == '>':
                    if depth:
                        depth -= 1
                    else:
                        self.statement(code[:i])
                        if not self.blocks:
                            raise ValueError(f"line {self.line}: unmatched block end")
                        closing, _ = self.blocks.pop()
                        self.emit(closing)
                        if closing == '.endmacro':
                            self.in_macro = None
                        self.parse(code[i + 1:])
                        return
        if depth or quoted:
            raise ValueError(f"line {self.line}: unbalanced expression or string")
        self.statement(code)

    def convert(self, source):
        delimiter = None
        skip_dt_body = False
        for self.line, line in enumerate(source.splitlines(), 1):
            if delimiter:
                self.emit('; ' + line)
                if line.strip() == delimiter:
                    delimiter = None
                continue
            comment = re.match(r'^\s*COMMENT\s+(.)', line, re.I)
            if comment:
                delimiter = comment[1]
                self.emit('; Original documentation:')
                continue
            if skip_dt_body:
                if line.strip() != 'IRPC\tQ,<IFDIF <Q><">,<EXP "Q">>>':
                    raise ValueError('Unexpected DT macro body')
                skip_dt_body = False
                continue
            if re.match(r'^DEFINE\s+DT\(Q\),<', line, re.I):
                self.emit('.macro DT text\n    .byte text\n.endmacro')
                skip_dt_body = True
                continue
            code, comment = split_comment(line)
            if comment:
                self.emit(comment)
            self.parse(code)
            if not line.strip():
                self.emit('')
        if self.blocks or delimiter or skip_dt_body:
            raise ValueError(f"Unclosed source blocks: {self.blocks}, comment {delimiter}")
        return '\n'.join(self.output) + '\n'


def convert_macro10_to_ca65(source_text):
    converted = Converter().convert(source_text)
    if 'REALIO .set 4\n' in converted:
        converted = add_imnotwopr_target(converted)
    return converted


def add_imnotwopr_target(source):
    """Keep the historical listing intact; add explicit native ca65 port hooks.

    Unique anchors deliberately fail if the listing changes underneath the port.
    The inactive hooks emit no bytes in the original REALIO=4 build.
    """
    def replace(old, new):
        nonlocal source
        if source.count(old) != 1:
            raise ValueError(f'Platform hook must match exactly once: {old!r}')
        source = source.replace(old, new)

    replace('REALIO .set 4\n', '.ifndef REALIO\nREALIO = 4\n.endif\n; REALIO=6 selects IMNOTWOPR.\n')
    replace('.if RORSW\n.macro BASIC_ROR',
            '.if REALIO = 6\n.include "imnotwopr_config.inc"\n.endif\n\n.if RORSW\n.macro BASIC_ROR')
    replace('.assert * = $0800, error, "Linker layout requires the original Apple configuration"',
            '.if REALIO = 6\n.assert * = $C000, error, "IMNOTWOPR ROM must start at $C000"\n'
            '.else\n.assert * = $0800, error, "Apple ROM must start at $0800"\n.endif')
    # Select the serial line editor while retaining FININL and the common INCHR.
    replace('.if (REALIO-4) <> 0\n.if (REALIO-3) <> 0\nLINLIN:',
            '.if (REALIO <> 4) && (REALIO <> 6)\n.if (REALIO-3) <> 0\nLINLIN:')
    replace('INCHR:\n', 'INCHR:\n.if REALIO = 6\n    jsr WOPR_GETC\n.endif\n')
    # The fixed RAM limit avoids both destructive probing and startup questions.
    start = source.index('    stx TEMPPT\n', source.index('\nINIT:\n')) + len('    stx TEMPPT\n')
    end = source.index('    STWD MEMSIZ\n', start)
    source = (source[:start] + '.if REALIO = 6\n    LDWDI WOPR_RAM_END\n.else\n'
              + source[start:end] + '.endif\n' + source[end:])
    replace('TTYW:\n', 'TTYW:\n.if REALIO <> 6\n')
    replace('.if (ROMSW) <> 0\n    LDXYI RAMLOC\n',
            '.endif ; historical terminal-width / optional-function questions\n'
            '.if (ROMSW) <> 0\n    LDXYI RAMLOC\n')
    replace('    DT "STM BASIC V1.1"\n.endif',
            '    DT "STM BASIC V1.1"\n.endif\n.if REALIO = 6\n'
            '    DT "IMNOTWOPR BASIC V1.1"\n.endif')
    return source + '\n.if REALIO = 6\n.include "imnotwopr.inc"\n.endif\n'


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    root = Path(__file__).resolve().parent
    parser.add_argument('source', nargs='?', type=Path, default=root / 'ms_basic_1978.asm')
    parser.add_argument('output', nargs='?', type=Path, default=root / 'm6502.s')
    args = parser.parse_args()
    args.output.write_text(convert_macro10_to_ca65(args.source.read_text()))
    print(f'Wrote {args.output}')
