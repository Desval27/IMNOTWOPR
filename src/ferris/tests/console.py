#!/usr/bin/env python3
"""Build Ferris with make, then run: python tests/console.py PATH/TO/joshua."""
import pathlib
import subprocess
import sys
import tempfile
import unittest

EXECUTABLE = pathlib.Path(sys.argv.pop(1)).resolve()
PROFILE = pathlib.Path(__file__).resolve().parents[2] / "joshua/profiles/ferris.profile"


class ConsoleTests(unittest.TestCase):
    def test_generic_comparison(self):
        labels = {}
        label_file = pathlib.Path(__file__).resolve().parents[1] / "ferris.lbl"
        for line in label_file.read_text().splitlines():
            _, address, name = line.split()
            labels[name.lstrip(".")] = int(address, 16)
        cases = [(b"", b"", True), (b"", b"x", False), (b"x", b"", False),
                 (b"joshua", b"joshua", True), (b"joshua", b"Joshua", False),
                 (b"joshu", b"joshua", False), (b"joshuax", b"joshua", False),
                 (b"A" * 300, b"A" * 300, True),
                 (b"A" * 300 + b"B", b"A" * 300 + b"C", False),
                 (b"\x80\xff", b"\x80\xff", True)]
        for left, right, equal in cases:
            with self.subTest(left_length=len(left), right_length=len(right), equal=equal):
                commands = []
                for name, address, data in [("compare_text_left", 0x30fe, left),
                                             ("compare_text_right", 0x35f9, right)]:
                    commands += [f"write {labels[name]:04X} {address & 255:02X} {address >> 8:02X}",
                                 f"write {address:04X} " + " ".join(f"{b:02X}" for b in data + b"\0")]
                commands += [f"asm 400 JSR ${labels['compare_text']:04X}",
                             "asm 403 STA $0600", "asm 406 PHP", "asm 407 PLA",
                             "asm 408 STA $0601", "asm 40B STX $0602", "asm 40E STP",
                             "regs x A5", "run 400"]
                with tempfile.TemporaryDirectory() as directory:
                    output = pathlib.Path(directory, "result.bin")
                    script = commands + [f'save "{output}" 600 3', "quit"]
                    result = subprocess.run(
                        [str(EXECUTABLE), "--profile", str(PROFILE), "--cycles", "10000", "--unthrottled"],
                        input=("\n".join(script) + "\n").encode(), capture_output=True, timeout=15)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    accumulator, flags, x = output.read_bytes()
                    self.assertEqual(accumulator, 0 if equal else 1)
                    self.assertEqual(bool(flags & 2), equal)
                    self.assertEqual(x, 0xa5)

    def check_console(self, typed, expected, login=True):
        if login:
            typed = b"joshua\r\n" + typed
            expected = b"joshua\r\nGREETINGS PROFESSOR FALKEN.\r\n> " + expected
        # Pace input so the polling receiver can finish echoing each character.
        commands = ["run"] * 5
        for byte in typed:
            commands += [f"send {byte:02X}", "run"]
            if byte in (10, 13):
                commands += ["run"] * 40  # Allow a full 255-byte reversal.
        commands += ["quit"]
        result = subprocess.run(
            [str(EXECUTABLE), "--profile", str(PROFILE), "--console-newline", "raw",
             "--cycles", "10000", "--unthrottled"],
            input=("\n".join(commands) + "\n").encode(), capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, b"login: " + expected)

    def test_initial_prompt(self):
        self.check_console(b"", b"", login=False)

    def test_login_rejection_and_retry(self):
        names = [b"", b"Joshua", b"JOSHUA", b"joshu", b"joshuax", b" joshua", b"joshua "]
        typed = b"".join(name + b"\r\n" for name in names)
        expected = b"".join(name + b"\r\nACCESS DENIED.\r\nlogin: " for name in names)
        self.check_console(typed + b"joshua\nTest\r",
                           expected + b"joshua\r\nGREETINGS PROFESSOR FALKEN.\r\n> Test\r\ntseT\r\n> ",
                           login=False)

    def test_reverse_and_line_endings(self):
        self.check_console(b"Hello\r\nWorld\n!\r",
                           b"Hello\r\nolleH\r\n> World\r\ndlroW\r\n> !\r\n!\r\n> ")

    def test_empty_and_editing(self):
        self.check_console(b"\r\x08ab\x08C\x7fD\r",
                           b"\r\n\r\n> ab\x08 \x08C\x08 \x08D\r\nDa\r\n> ")

    def test_capacity_and_reuse(self):
        text = (b"abcde" * 51)
        self.check_console(text + b"Z\x08Q\rOK\r",
                           text + b"\x07\x08 \x08Q\r\n" + (text[:-1] + b"Q")[::-1]
                           + b"\r\n> OK\r\nKO\r\n> ")

    def test_ignore_other_control_bytes(self):
        self.check_console(b"a\x00\x01\xffb\r", b"ab\r\nba\r\n> ")


if __name__ == "__main__":
    unittest.main()
