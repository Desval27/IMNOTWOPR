#!/usr/bin/env python3
"""Build with make monitor, then run: python tests/monitor.py PATH/TO/joshua."""
import pathlib
import subprocess
import sys
import unittest

EXECUTABLE = pathlib.Path(sys.argv.pop(1)).resolve()
ROOT = pathlib.Path(__file__).resolve().parents[1]
PROFILE = ROOT.parent / "joshua/profiles/monitor.profile"
USAGE = b"usage: mem low_address high_address (1-4 hex digits, inclusive)\r\n"


def dump(address, data):
    rows = []
    for offset in range(0, len(data), 16):
        row = data[offset:offset + 16]
        hexadecimal = " ".join(f"{byte:02X}" for byte in row)
        ascii_text = "".join(chr(byte) if 32 <= byte < 127 else "." for byte in row)
        rows.append(f"{address + offset:04X}: {hexadecimal:<47}  |{ascii_text}|\r\n")
    return "".join(rows).encode()


class MonitorTests(unittest.TestCase):
    def check_commands(self, cases, setup=()):
        commands = list(setup) + ["run"] * 5
        expected = b": "
        for line, output in cases:
            for byte in line + b"\r":
                commands += [f"send {byte:02X}", "run"]
            commands += ["run"] * 100
            expected += line + b"\r\n" + output + b": "
        commands += ["quit"]
        result = subprocess.run(
            [str(EXECUTABLE), "--profile", str(PROFILE), "--console-newline", "raw",
             "--cycles", "10000", "--unthrottled"],
            input=("\n".join(commands) + "\n").encode(), capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, expected)

    def test_rows_ascii_and_page_crossing(self):
        data = bytes([0, 31, 32, 33, 65, 90, 97, 122, 126, 127, 128, 255]) + b"0123456789ABC"
        self.check_commands(
            [(b"mem 30f8 3110", dump(0x30f8, data)),
             (b"mem 30F8 3107", dump(0x30f8, data[:16])),
             (b"mem 30fA 30Fa", dump(0x30fa, data[2:3]))],
            ["write 30F8 " + " ".join(f"{byte:02X}" for byte in data)])

    def test_short_addresses(self):
        self.check_commands([(b"mem 900 901", dump(0x900, b"AB"))], ["write 900 41 42"])

    def test_end_of_address_space(self):
        rom = (ROOT / "monitor.bin").read_bytes()
        self.check_commands([(b"mem fff0 ffff", dump(0xfff0, rom[-16:])),
                             (b"mem FFFF FFFF", dump(0xffff, rom[-1:]))])

    def test_invalid_arguments_and_recovery(self):
        invalid = [b"mem", b"mem 900", b"mem 900 901 902", b'mem "" 900',
                   b'mem 900 ""', b"mem G 900", b"mem 900 90G", b"mem / 900",
                   b"mem : 900", b"mem @ 900", b"mem 900 `", b"mem 10000 FFFF",
                   b"mem 900 00000", b"mem -1 900", b"mem 0x900 901",
                   b"mem 901 900", b"mem 1000 FFF", b'mem "9 00" 901']
        self.check_commands([(line, USAGE) for line in invalid]
                            + [(b"mem 900 900", dump(0x900, b"!"))], ["write 900 21"])


if __name__ == "__main__":
    unittest.main()
