"""Conversion regressions plus byte/layout checks on the linked default build."""
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

from convert import convert_macro10_to_ca65

ROOT = Path(__file__).resolve().parent


class ConversionTests(unittest.TestCase):
    def test_generated_source_is_current(self):
        original = (ROOT / 'ms_basic_1978.asm').read_text()
        self.assertEqual(convert_macro10_to_ca65(original), (ROOT / 'm6502.s').read_text())

    def assemble_fragment(self, source):
        """Check actual bytes, so syntax-valid but incorrect conversions also fail."""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / 'test.s').write_text(convert_macro10_to_ca65(source))
            (path / 'test.cfg').write_text('''
MEMORY { RAM: start = 0, size = $10000, file = %O; }
SEGMENTS { LOWRAM: load = RAM, type = rw; }
''')
            subprocess.run(['ca65', '-o', str(path / 'test.o'), str(path / 'test.s')], check=True)
            subprocess.run(['ld65', '-C', str(path / 'test.cfg'), '-o', str(path / 'test.bin'),
                            str(path / 'test.o')], check=True)
            return (path / 'test.bin').read_bytes()

    def test_nested_blocks_expressions_and_comments(self):
        self.assertEqual(self.assemble_fragment('''
RADIX 10
IFE 0,<
DEFINE PAIR(WD),<
    LDAI <<WD>&^O377>
    LDYI <<WD>/^O400>>
IFN 1,<PAIR ^O123456>> ; brackets in comments <> must be ignored
IFE 1,<99>
DEFINE INCW(R),<
    INC R
    BNE %Q
    INC R+1
%Q:>
    INCW 0
    INCW 2
'''), bytes.fromhex('a9 2e a0 a7 e6 00 d0 02 e6 01 e6 02 d0 02 e6 03'))

    def test_strings_radix_and_opcode_markers(self):
        self.assertEqual(self.assemble_fragment('''
DEFINE DT(Q),<
IRPC	Q,<IFDIF <Q><">,<EXP "Q">>>
    DT"a;<>"
    DC"END"
    XWD ^O1000,^O044
RADIX 8
    200
    377
    LDAI ^D256-7
    CMPI "a"
RADIX 10
    128
    255
'''), b'a;<>' + b'EN\xc4' + bytes.fromhex('24 80 ff a9 f9 c9 61 80 ff'))

    def test_comment_delimiters_and_unclosed_blocks(self):
        self.assertEqual(self.assemble_fragment('''
COMMENT %
This * is not the end, nor are these < > brackets.
%
    42
'''), b'\x2a')
        with self.assertRaisesRegex(ValueError, 'Unclosed source blocks'):
            convert_macro10_to_ca65('IFE 0,<1')
        with self.assertRaisesRegex(ValueError, 'unmatched block end'):
            convert_macro10_to_ca65('1>')


class ImageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.basic = (ROOT / 'm6502.bin').read_bytes()
        cls.lowram = (ROOT / 'm6502-lowram.bin').read_bytes()
        cls.labels = {name: int(address, 16) for address, name in re.findall(
            r'^al ([0-9A-Fa-f]+) \.(\w+)$', (ROOT / 'm6502.lbl').read_text(), re.M)}

    def data(self, name, length):
        address = self.labels[name] - 0x0800
        return self.basic[address:address + length]

    def test_original_layout_and_dispatch(self):
        self.assertEqual(self.labels['START'], 0)
        self.assertEqual(self.labels['STMDSP'], 0x0800)
        self.assertEqual(self.labels['LOFBUF'], 0xff)
        self.assertEqual(self.labels['FBUFFR'], 0x100)
        self.assertEqual(len(self.lowram), 0x110)
        self.assertLessEqual(0x0800 + len(self.basic), 0x2a00)
        self.assertEqual(self.lowram[:3], b'\x4c' + self.labels['INIT'].to_bytes(2, 'little'))
        # RTS dispatch entries contain addresses minus one, in little endian.
        expected = b''.join((self.labels[name] - 1).to_bytes(2, 'little')
                            for name in ('END', 'FOR', 'NEXT', 'DATA'))
        self.assertEqual(self.data('STMDSP', len(expected)), expected)

    def test_tokens_messages_and_floating_point_constants(self):
        self.assertEqual(self.data('RESLST', 14), b'EN\xc4FO\xd2NEX\xd4DAT\xc1')
        self.assertEqual(self.data('ERRTAB', 6), b'N\xc6S\xceR\xc7')
        # DT must concatenate strings without adding zero bytes between them.
        self.assertEqual(self.data('WORDS', 26), b' BYTES FREE\r\n\r\nAPPLE BASIC')
        self.assertEqual(self.data('FHALF', 5), bytes.fromhex('80 00 00 00 00'))
        self.assertEqual(self.data('FONE', 5), bytes.fromhex('81 00 00 00 00'))


if __name__ == '__main__':
    unittest.main()
