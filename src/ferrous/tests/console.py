#!/usr/bin/env python3
"""Build Ferrous with make, then run: python tests/console.py PATH/TO/joshua."""
import pathlib
import subprocess
import sys
import tempfile
import unittest

EXECUTABLE = pathlib.Path(sys.argv.pop(1)).resolve()
PROFILE = pathlib.Path(__file__).resolve().parents[2] / "joshua/profiles/ferrous.profile"


class ConsoleTests(unittest.TestCase):
    def test_generic_comparison(self):
        labels = {}
        label_file = pathlib.Path(__file__).resolve().parents[1] / "ferrous.lbl"
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

    def check_console(self, typed, expected, wake=True):
        if wake:
            typed = b"\r\n" + typed
            expected = b"\r\nwhat? " + expected
        # Pace input so the polling receiver can finish echoing each character.
        commands = ["run"] * 5
        for byte in typed:
            commands += [f"send {byte:02X}", "run"]
            if byte in (10, 13):
                commands += ["run"] * 60  # Allow maximum-length itemized output.
        commands += ["quit"]
        result = subprocess.run(
            [str(EXECUTABLE), "--profile", str(PROFILE), "--console-newline", "raw",
             "--cycles", "10000", "--unthrottled"],
            input=("\n".join(commands) + "\n").encode(), capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, expected)

    def test_initial_prompt(self):
        self.check_console(b"", b"", wake=False)
        self.check_console(b"", b"")

    @staticmethod
    def items(*values):
        return b"".join(f"  [{i}] ".encode() + value + b"\r\n"
                        for i, value in enumerate(values, 1))

    def test_echo_and_line_endings(self):
        self.check_console(b"echo Hello World\r\necho !\necho\r",
                           b"echo Hello World\r\n" + self.items(b"Hello", b"World")
                           + b"what? echo !\r\n" + self.items(b"!")
                           + b"what? echo\r\n\r\nwhat? ")

    def test_unknown_and_exact_names(self):
        lines = [b"Echo", b"ECHO", b"ech", b"echox", b"unknown x y", b'  nope "a b"  ', b'""']
        self.check_console(b"".join(line + b"\r" for line in lines) + b"echo ok\r",
                           b"".join(line + b"\r\nunrecognized command " + line
                                    + b"\r\nwhat? " for line in lines)
                           + b"echo ok\r\n" + self.items(b"ok") + b"what? ")

    def test_spaces_and_quotes(self):
        line = b'  echo   one "two three" "" pre" mid "post "a\\b"  '
        self.check_console(line + b"\r", line + b"\r\n"
                           + self.items(b"one", b"two three", b"", b"pre mid post", b"a\\b")
                           + b"what? ")
        self.check_console(b'"echo" "hi"\r', b'"echo" "hi"\r\n'
                           + self.items(b"hi") + b"what? ")

    def test_malformed_and_recovery(self):
        lines = [b'echo "unterminated', b'echo good bad"', b"echo " + b"x " * 16]
        error = b"malformed command (unclosed quote or too many parameters)\r\nwhat? "
        self.check_console(b"".join(line + b"\r" for line in lines) + b"echo ok\r",
                           b"".join(line + b"\r\n" + error for line in lines)
                           + b"echo ok\r\n" + self.items(b"ok") + b"what? ")

    def test_parameter_limit(self):
        values = [str(i).encode() for i in range(1, 16)]
        line = b"echo " + b" ".join(values) + b"   "
        self.check_console(line + b"\r", line + b"\r\n" + self.items(*values) + b"what? ")
        line = b"echo " + b" ".join([b'""'] * 15)
        self.check_console(line + b"\r", line + b"\r\n" + self.items(*([b""] * 15)) + b"what? ")

    def test_empty_and_editing(self):
        self.check_console(b"\r   \r\x08echo ab\x08C\x7fD\r",
                           b"\r\nwhat?    \r\nwhat? echo ab\x08 \x08C\x08 \x08D\r\n"
                           + self.items(b"aD") + b"what? ")

    def test_capacity_and_reuse(self):
        text = b"echo " + b"abcde" * 50
        self.check_console(text + b"Z\x08Q\recho OK\r",
                           text + b"\x07\x08 \x08Q\r\n" + self.items(text[5:-1] + b"Q")
                           + b"what? echo OK\r\n" + self.items(b"OK") + b"what? ")
        # A full buffer ending in a separator must not wrap either parse index.
        text = b"echo " + b"x" * 249 + b" "
        self.check_console(text + b"\r", text + b"\r\n" + self.items(b"x" * 249) + b"what? ")
        self.check_console(b" " * 255 + b"\r", b" " * 255 + b"\r\nwhat? ")

    def test_ignore_other_control_bytes(self):
        self.check_console(b"echo a\x00\x01\xffb\r",
                           b"echo ab\r\n" + self.items(b"ab") + b"what? ")


if __name__ == "__main__":
    unittest.main()
