"""Boot and exercise REALIO=6 in Joshua. Usage: python3 test_imnotwopr.py JOSHUA"""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent
JOSHUA = Path(sys.argv.pop(1)).resolve()
PROFILE = ROOT.parent / 'joshua/profiles/m6502.profile'
ROM = (ROOT / 'm6502-imnotwopr.bin').read_bytes()
LABELS = {name.lstrip('.'): int(address, 16)
          for _, address, name in (line.split() for line in (ROOT / 'm6502-imnotwopr.lbl').read_text().splitlines())}
BANNER = (b'\r\n\r\n 43519 BYTES FREE\r\n\r\nIMNOTWOPR BASIC V1.1\r\n'
          b'COPYRIGHT 1978 MICROSOFT\r\n\r\nOK\r\n')
PROMPT = b'\r\nOK\r\n'


def send(data):
    return 'send ' + ' '.join(f'{byte:02X}' for byte in data)


def line(text):
    return [send(text.encode('ascii') + b'\r'), 'run']


class ImnotwoprTests(unittest.TestCase):
    def run_basic(self, commands, *, capture=False):
        with tempfile.TemporaryDirectory() as directory:
            ram = Path(directory) / 'ram.bin'
            dump = [f'save "{ram}" 0 B000'] if capture else []
            result = subprocess.run(
                [str(JOSHUA), '--profile', str(PROFILE), '--console-newline', 'raw',
                 '--cycles', '1000000', '--unthrottled'],
                input=('\n'.join(['run'] + commands + dump + ['quit']) + '\n').encode(),
                capture_output=True, timeout=40)
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            self.assertTrue(result.stdout.startswith(BANNER), result.stdout)
            if capture:
                return result.stdout[len(BANNER):], ram.read_bytes()
            return result.stdout[len(BANNER):]

    def test_rom_boot_and_ram_initialization(self):
        self.assertEqual(len(ROM), 0x4000)
        for offset, name in ((0x3ffa, 'WOPR_NMI'), (0x3ffc, 'WOPR_RESET'), (0x3ffe, 'WOPR_IRQ')):
            self.assertEqual(int.from_bytes(ROM[offset:offset+2], 'little'), LABELS[name])
        self.assertEqual(LABELS['STMDSP'], 0xc000)
        output, ram = self.run_basic([], capture=True)
        self.assertEqual(output, b'')
        def word(name):
            addr = LABELS[name]
            return int.from_bytes(ram[addr:addr+2], 'little')
        self.assertEqual(word('MEMSIZ'), 0xb000)
        self.assertEqual(word('FRETOP'), 0xb000)
        self.assertEqual(word('TXTTAB'), 0x0601)
        self.assertEqual(ram[LABELS['START']], 0x4c)
        self.assertEqual(int.from_bytes(ram[1:3], 'little'), LABELS['READY'])
        self.assertEqual(ram[LABELS['CHRGET']], 0xe6)  # INC zp, writable code.
        self.assertEqual(ram[0x600:0x604], b'\0' * 4)

    def test_math_strings_and_error_recovery(self):
        output = self.run_basic(
            line('PRINT 2+3*4') + line('PRINT "Hello, IMNOTWOPR"')
            + line('PRINT SQR(81);SIN(0);LEN("ABC")') + line('PRINT 1/0') + line('PRINT 42'))
        self.assertIn(b' 14 \r\n', output)
        self.assertIn(b'\r\nHello, IMNOTWOPR\r\n', output)
        self.assertIn(b' 9  0  3 \r\n', output)
        self.assertIn(b'?/0 ERROR\r\nOK\r\n', output)
        self.assertTrue(output.endswith(b' 42 \r\n' + PROMPT), output)
        self.assertTrue(all(byte < 128 for byte in output))

    def test_program_storage_arrays_gosub_and_new(self):
        commands = []
        for text in ('10 DIM A(3):FOR I=1 TO 3:A(I)=I*I:NEXT I',
                     '20 GOSUB 100:END', '100 PRINT A(3):RETURN', 'LIST', 'RUN',
                     '10 PRINT 123', 'RUN', 'NEW', 'LIST'):
            commands += line(text)
        output = self.run_basic(commands)
        self.assertIn(b' 100 PRINT A(3):RETURN\r\n', output)
        self.assertIn(b'RUN\r\n 9 \r\n', output)
        self.assertIn(b'RUN\r\n 123 \r\n', output)
        self.assertNotIn(b' ERROR', output)
        self.assertTrue(output.endswith(b'LIST\r\n\r\nOK\r\n'), output)

    def test_input_newlines_and_editing(self):
        commands = line('10 INPUT "NUMBER";A') + line('RUN') + line('7') + line('PRINT A*2')
        commands += [send(b'PRINT 12\x08\x7f3\r\nPRINT 4\n'), 'run']
        commands += [send(b'WRONG\x15PRINT 5\r'), 'run']
        output = self.run_basic(commands)
        self.assertIn(b'NUMBER? 7\r\n', output)
        self.assertIn(b' 14 \r\n', output)
        self.assertIn(b'PRINT 12\x08 \x08\x08 \x083\r\n 3 \r\n', output)
        self.assertIn(b'PRINT 4\r\n 4 \r\n', output)
        self.assertTrue(output.endswith(b'PRINT 5\r\n 5 \r\n' + PROMPT), output)
        self.assertNotIn(b' ERROR', output)

    def test_control_c_and_continue(self):
        commands = line('10 I=I+1:GOTO 10') + line('RUN')
        commands += [send(b'\x03'), 'run'] + line('CONT') + [send(b'\x03'), 'run']
        commands += line('PRINT 99')
        output = self.run_basic(commands)
        self.assertEqual(output.count(b'BREAK IN  10'), 2, output)
        self.assertTrue(output.endswith(b' 99 \r\n' + PROMPT), output)

    def test_get_nonblocking(self):
        commands = line('10 GET A$:IF A$="" THEN 10') + line('20 PRINT ASC(A$):END') + line('RUN')
        commands += [send(b'Z'), 'run']
        output = self.run_basic(commands)
        self.assertTrue(output.endswith(b'RUN\r\n 90 \r\n' + PROMPT), output)

    def test_queue_overflow_reports_and_recovers(self):
        commands = line('10 GOTO 10') + line('RUN')
        commands += [send(b'x' * 260 + b'\r'), 'run'] + line('PRINT 6')
        output = self.run_basic(commands)
        self.assertIn(b'?SERIAL INPUT OVERFLOW/ERROR', output)
        self.assertTrue(output.endswith(b' 6 \r\n' + PROMPT), output)

    def test_reset_restores_ram_code(self):
        commands = line('10 PRINT "OLD"') + [f'write {LABELS["CHRGET"]:04X} FF', 'reset', 'run']
        commands += line('LIST') + line('PRINT 8')
        output = self.run_basic(commands)
        self.assertIn(BANNER, output)
        self.assertIn(b'LIST\r\n\r\nOK\r\n', output)
        self.assertTrue(output.endswith(b' 8 \r\n' + PROMPT), output)

    def test_full_line_does_not_corrupt_program_storage(self):
        text = '10 REM ' + 'x' * 72
        commands = [send(text.encode() + b'Z\r'), 'run']
        commands += line('LIST') + line('RUN') + line('PRINT 42')
        output = self.run_basic(commands)
        self.assertIn(text.encode() + b'\x07\r\n', output)
        self.assertIn(b' 10 REM ' + b'x' * 72 + b'\r\n', output)
        self.assertNotIn(b' ERROR', output)
        self.assertTrue(output.endswith(b' 42 \r\n' + PROMPT), output)


if __name__ == '__main__':
    unittest.main()
