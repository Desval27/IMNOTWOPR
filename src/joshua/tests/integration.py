#!/usr/bin/env python3
"""CLI, profile, serial and monitor integration checks. No third-party modules."""
import os
import pathlib
import subprocess
import sys
import tempfile
import time
import unittest
import zlib

EXECUTABLE = pathlib.Path(sys.argv.pop(1)).resolve()
PROJECT = pathlib.Path(__file__).resolve().parent.parent


class Integration(unittest.TestCase):
    def run_script(self, commands, *arguments, directory=None):
        return subprocess.run([str(EXECUTABLE), *arguments], input=commands.encode(),
                              capture_output=True, cwd=directory or PROJECT, timeout=15)

    def test_echo(self):
        result = self.run_script("send 48 65 6C 6C 6F 0D\nrun\nquit\n",
                                 "--profile", "profiles/echo.profile", "--cycles", "20000", "--unthrottled")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, b">Hello\r\n")

    def test_load_save_and_invalid_ranges(self):
        with tempfile.TemporaryDirectory() as directory:
            source = pathlib.Path(directory, "input file.bin")
            source.write_bytes(bytes(range(256)))
            result = self.run_script('load "input file.bin" C000\nsave "output file.bin" C000 100\nquit\n', directory=directory)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(pathlib.Path(directory, "output file.bin").read_bytes(), source.read_bytes())
            result = self.run_script('load "input file.bin" 7FF0\nsave result.bin 7FF0 10\nquit\n', directory=directory)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(pathlib.Path(directory, "result.bin").read_bytes(), bytes(16))

    def test_console_newlines(self):
        # Drain each byte separately to exercise CR/LF pairs across drain calls.
        setup = "asm 200 BRA 200\nregs pc 200\nio write 8013 1F\nio write 8012 0B\n"
        data = b"A\rB\nC\r\nD\r\rE\n\n\x00\xff"
        output = "".join(f"io write 8010 {byte:02X}\nstep 300\n" for byte in data)
        expected = {
            "raw": data,
            "cr": b"A\r\nB\nC\r\nD\r\n\r\nE\n\n\x00\xff",
            "lf": b"A\rB\r\nC\r\nD\r\rE\r\n\r\n\x00\xff",
            "auto": b"A\r\nB\r\nC\r\nD\r\n\r\nE\r\n\r\n\x00\xff",
        }
        for mode, wanted in expected.items():
            with self.subTest(mode=mode):
                result = self.run_script(setup + output + "quit\n", "--console-newline", mode)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, wanted)
                result = self.run_script(f"console-newline {mode}\nreset\nconsole-newline\n" + setup + output + "quit\n")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, wanted)
                self.assertEqual(result.stderr.count(f"Console newline: {mode}".encode()), 2)

        with tempfile.TemporaryDirectory() as directory:
            profile = pathlib.Path(directory, "newline.profile")
            profile.write_text("console-newline = cr\n")
            result = self.run_script(setup + output + "quit\n", "--profile", str(profile))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, expected["cr"])
            for args in (("--console-newline", "raw", "--profile", str(profile)),
                         ("--profile", str(profile), "--console-newline", "raw")):
                result = self.run_script(setup + output + "quit\n", *args)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, data)
            profile.write_text("console-newline = invalid\n")
            result = self.run_script("quit\n", "--profile", str(profile))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b"newline.profile:1:", result.stderr)
        for commands, args in (("quit\n", ("--console-newline", "invalid")),
                               ("console-newline invalid\nquit\n", ())):
            result = self.run_script(commands, *args)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b"console-newline must be", result.stderr)

    def test_save_load_state(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            result = self.run_script(
                'asm 200 INC A\nasm 201 BRA 200\nregs pc 200\nstep\n'
                'write C000 42\nbreak 201\nbreak disable 201\n'
                'serial 9600 7 even 1\nconsole-newline auto\n'
                'save-state "saved state.jss"\nquit\n', directory=directory)
            self.assertEqual(result.returncode, 0, result.stderr)
            saved = root.joinpath("saved state.jss").read_bytes()
            # Restore in a new process and check continuation cursors and execution.
            result = self.run_script(
                'mem 400 L 1\ndis 400 L 1\nload-state "saved state.jss"\n'
                'save-state roundtrip.jss\nmem N L 1\ndis N L 1\n'
                'step 2\nregs\nserial\nconsole-newline\nbreak\nquit\n', directory=directory)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(root.joinpath("roundtrip.jss").read_bytes(), saved)
            self.assertIn(b"PC=0201 A=02", result.stderr)
            self.assertIn(b"9600 baud, 7 data bits, parity=even", result.stderr)
            self.assertIn(b"Console newline: auto", result.stderr)
            self.assertIn(b"0201 disabled", result.stderr)
            self.assertEqual(result.stderr.count(b"0201  "), 2)

            invalid = {
                "magic": b"INVALID!" + saved[8:],
                "version": saved[:8] + (99).to_bytes(4, "little") + saved[12:],
                "truncated": saved[:-1],
                "extra": saved + b"extra",
                "checksum": saved[:-1] + bytes([saved[-1] ^ 1]),
                "oversize": saved[:12] + (2**32 - 1).to_bytes(4, "little") + saved[16:],
            }
            # Invalid boolean at the end, with a valid checksum: parse failure
            # after all memory and devices have been staged must be transactional.
            payload = saved[20:-1] + b"\x02"
            invalid["boolean"] = saved[:16] + zlib.crc32(payload).to_bytes(4, "little") + payload
            # A valid checksum on a short payload exercises internal bounds checks.
            payload = saved[20:35]
            invalid["short_payload"] = (saved[:12] + len(payload).to_bytes(4, "little")
                                        + zlib.crc32(payload).to_bytes(4, "little") + payload)
            for name, content in invalid.items():
                with self.subTest(name=name):
                    root.joinpath("bad.jss").write_bytes(content)
                    result = self.run_script(
                        'save-state before.jss\nload-state bad.jss\nsave-state after.jss\nquit\n',
                        directory=directory)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(b"Error:", result.stderr)
                    self.assertEqual(root.joinpath("before.jss").read_bytes(),
                                     root.joinpath("after.jss").read_bytes())
            for command in ('save-state', 'load-state', 'save-state one two', 'load-state one two'):
                result = self.run_script(command + '\nquit\n', directory=directory)
                self.assertNotEqual(result.returncode, 0)

    def test_restored_breakpoint_is_not_bypassed(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.run_script(
                'asm 200 INC A\nasm 201 BRA 200\nregs pc 200\nbreak 200\n'
                'save-state paused.jss\nrun\nload-state paused.jss\nrun\nregs\nquit\n',
                '--cycles', '100', '--unthrottled', directory=directory)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stderr.count(b"Breakpoint at $0200."), 2)
            self.assertNotIn(b"A=01", result.stderr)

    def test_wozmon_dump_newlines(self):
        # Let firmware initialize, then type slowly enough for its polling receiver.
        commands = "run\n" + "".join(f"send {byte:02X}\nrun\n" for byte in b"0300.03FF\r") + "quit\n"
        result = self.run_script(commands, "--profile", "profiles/wozmon.profile",
                                 "--cycles", "2000000", "--unthrottled")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(b"\r\n0300:", result.stdout)
        self.assertIn(b"\r\n03F8:", result.stdout)
        self.assertNotIn(b"\r\r\n", result.stdout)
        self.assertNotIn(b"\r", result.stdout.replace(b"\r\n", b""))

    def test_profile_relative_paths_and_cli_precedence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            root.joinpath("boot.bin").write_bytes(bytes([0xa9, 0x42]))
            profile = root / "machine.profile"
            profile.write_text("ram = 0:8000\nrom = C000:4000:boot.bin\nvia = none\nacia = none\npc = C000\n")
            result = self.run_script("step\nquit\n", "--profile", str(profile))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(b"A=42", result.stderr)
            for args in (("--ram", "0:10000", "--rom", "none", "--profile", str(profile)),
                         ("--profile", str(profile), "--ram", "0:10000", "--rom", "none")):
                result = self.run_script("map\nquit\n", *args)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(b"0000-FFFF RAM0", result.stderr)
                self.assertNotIn(b"C000-FFFF ROM0", result.stderr)

    def test_bad_config(self):
        for args in (("--ram", "0:10000"), ("--via", "FFFF"), ("--clock-hz", "0"),
                     ("--clock-hz", "-1"), ("--rom", "FFFF:2"), ("--pc", "10000"), ("--cycles", "0")):
            result = self.run_script("quit\n", *args)
            self.assertNotEqual(result.returncode, 0, args)

    def test_breakpoint_resume(self):
        result = self.run_script("asm 200 INC A\nasm 201 BRA 200\nbreak 200\nrun 200\nregs\nrun\nregs\nquit\n",
                                 "--cycles", "100", "--unthrottled")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr.count(b"Breakpoint at $0200."), 2)
        self.assertIn(b"PC=0200 A=01", result.stderr)

    @unittest.skipIf(os.name == "nt", "POSIX pseudo-terminal test; Windows requires a native console")
    def test_terminal_escape_and_restore(self):
        import pty
        import select
        import termios
        master, slave = pty.openpty()
        before = termios.tcgetattr(slave)
        process = subprocess.Popen([str(EXECUTABLE), "--profile", str(PROJECT / "profiles/echo.profile"), "--run"],
                                   stdin=slave, stdout=slave, stderr=slave)

        def read_until(token):
            data = bytearray()
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                if select.select([master], [], [], 0.05)[0]:
                    data.extend(os.read(master, 4096))
                    if token in data:
                        return bytes(data)
            self.fail(f"terminal did not produce {token!r}: {bytes(data)!r}")

        try:
            read_until(b">")
            self.assertFalse(termios.tcgetattr(slave)[3] & termios.ECHO)
            os.write(master, b"Z")
            self.assertEqual(read_until(b"Z"), b"Z")
            os.write(master, b"\r")  # Enter sends CR; the demo must also transmit LF.
            newline = read_until(b"\n")
            self.assertEqual(newline.replace(b"\r", b""), b"\n")
            os.write(master, b"\x1d")
            read_until(b"joshua> ")
            self.assertEqual(termios.tcgetattr(slave), before)
            os.write(master, b"run\n")
            read_until(b"Running;")
            os.write(master, b"\x03")
            read_until(b"\x03")  # Ctrl-C reaches the guest while running.
            os.write(master, b"\x1d")
            read_until(b"joshua> ")
            os.write(master, b"quit\n")
            self.assertEqual(process.wait(timeout=5), 0)
            self.assertEqual(termios.tcgetattr(slave), before)
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)
            os.close(master)
            os.close(slave)


if __name__ == "__main__":
    unittest.main()
