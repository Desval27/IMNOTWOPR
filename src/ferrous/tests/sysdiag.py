#!/usr/bin/env python3
"""Run after make sysdiag: python3 tests/sysdiag.py PATH/TO/joshua."""
import pathlib
import subprocess
import sys
import tempfile
import unittest

EXECUTABLE = pathlib.Path(sys.argv.pop(1)).resolve()
ROOT = pathlib.Path(__file__).resolve().parents[1]
PROFILE = ROOT.parent / "joshua/profiles/sysdiag.profile"
LABELS = {}
for line in (ROOT / "sysdiag.lbl").read_text().splitlines():
    _, address, name = line.split()
    LABELS[name.lstrip(".")] = int(address, 16)


class MemoryRangeTests(unittest.TestCase):
    def run_monitor(self, commands, cycles=10000):
        result = subprocess.run(
            [str(EXECUTABLE), "--profile", str(PROFILE), "--console-newline", "raw",
             "--cycles", str(cycles), "--unthrottled"],
            input=("\n".join(commands + ["quit"]) + "\n").encode(),
            capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        return result.stdout

    def test_hex_parser(self):
        cases = {"0": 0, "f": 15, "aB": 0xab, "123": 0x123, "0000": 0,
                 "1234": 0x1234, "aBcD": 0xabcd, "FFFF": 0xffff,
                 "": None, "12345": None, "0x12": None, "$123": None,
                 " 123": None, "123 ": None, "12G4": None, "-1": None,
                 ":": None, "@": None, "[": None, "`": None, "g": None}
        for typed, expected in cases.items():
            with self.subTest(typed=typed), tempfile.TemporaryDirectory() as directory:
                output = pathlib.Path(directory, "result.bin")
                commands = [
                    f"write {LABELS['input_buffer']:04X} "
                    + " ".join(f"{b:02X}" for b in typed.encode() + b"\0"),
                    f"asm 400 JSR ${LABELS['parse_hex_address']:04X}",
                    "asm 403 STA $0500", "asm 406 STX $0501",
                    "asm 409 PHP", "asm 40A PLA", "asm 40B STA $0502",
                    "asm 40E STP", f"regs y {len(typed):02X}", "run 400",
                    f'save "{output}" 500 3']
                self.run_monitor(commands)
                low, high, flags = output.read_bytes()
                self.assertEqual(bool(flags & 1), expected is None)
                if expected is not None:
                    self.assertEqual(low | high << 8, expected)

    def test_inclusive_loop(self):
        for start, end in [(0, 0), (0xfe, 0x102), (0xfffe, 0xffff), (0, 0xffff)]:
            with self.subTest(start=start, end=end), tempfile.TemporaryDirectory() as directory:
                commands = [
                    f"write {LABELS['mem_test_start']:04X} {start & 255:02X} {start >> 8:02X}",
                    f"write {LABELS['mem_test_end']:04X} {end & 255:02X} {end >> 8:02X}",
                    "write 500 00",
                    f"asm 400 JSR ${LABELS['mem_test_begin']:04X}",
                    "asm 403 LDA #$A5", "asm 405 STA $0500", "asm 408 STP"]
                # Observe every iteration of short ranges, including both endpoints.
                if end - start < 10:
                    commands += [f"break {LABELS['mem_test_loop']:04X}",
                                 "run 400"]
                    for address in range(start, end + 1):
                        output = pathlib.Path(directory, f"{address}.bin")
                        commands += [f'save "{output}" {LABELS["mem_test_addr"]:04X} 2', "run"]
                else:
                    commands += ["run 400"]
                output = pathlib.Path(directory, "final.bin")
                commands += [f'save "{output}" {LABELS["mem_test_addr"]:04X} 2',
                             f'save "{directory}/bounds.bin" {LABELS["mem_test_start"]:04X} 4',
                             f'save "{directory}/returned.bin" 500 1']
                self.run_monitor(commands, cycles=5000000)
                self.assertEqual(pathlib.Path(directory, "returned.bin").read_bytes(), b"\xa5")
                self.assertEqual(int.from_bytes(output.read_bytes(), "little"), end)
                self.assertEqual(pathlib.Path(directory, "bounds.bin").read_bytes(),
                                 start.to_bytes(2, "little") + end.to_bytes(2, "little"))
                if end - start < 10:
                    for address in range(start, end + 1):
                        self.assertEqual(int.from_bytes(
                            pathlib.Path(directory, f"{address}.bin").read_bytes(), "little"), address)

    def test_prompts_and_retries(self):
        commands = ["run"] * 10
        typed = b"1\r\n\r0x12\r10000\r00fE\r\ng\r00fd\r0102\r"
        for byte in typed:
            commands += [f"send {byte:02X}", "run"]
            if byte in (10, 13):
                commands += ["run"] * 20
        with tempfile.TemporaryDirectory() as directory:
            output = pathlib.Path(directory, "bounds.bin")
            commands += [f'save "{output}" {LABELS["mem_test_start"]:04X} 4']
            stdout = self.run_monitor(commands)
            self.assertEqual(stdout.count(b"ENTER 1-4 HEX DIGITS (NO PREFIX)"), 4)
            self.assertIn(b"END MUST BE >= START\r\nEND: ", stdout)
            self.assertEqual(stdout.count(b"SYSTEM DIAGNOSTICS"), 2)
            self.assertEqual(output.read_bytes(), b"\xfe\x00\x02\x01")


if __name__ == "__main__":
    unittest.main()
