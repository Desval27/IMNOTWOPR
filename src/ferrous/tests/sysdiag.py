#!/usr/bin/env python3
"""Serial menu and I2C scan checks; build sysdiag first.

Usage: python3 tests/sysdiag.py PATH/TO/joshua -v
The responding-device tests inject SDA/SCL through RAM-backed VIA registers;
they exercise the ROM and real serial output, not an electrical I2C target.
"""
import pathlib
import re
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
READ = LABELS["read_text"]
HIGH = LABELS["i2c_scl_high"]


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


class SysdiagTests(unittest.TestCase):
    def run_menu(self, commands, *, simulated=False):
        result = subprocess.run(
            [str(EXECUTABLE), "--ram", "0:B010" if simulated else "0:B000",
             "--via", "none" if simulated else "B000", "--acia", "B010",
             "--rom", f"C000:4000:{ROOT / 'sysdiag.bin'}", "--clock-hz", "1000000",
             "--serial-baud", "19200", "--console-newline", "raw",
             "--cycles", "1000000", "--unthrottled"],
            input=("\n".join([f"break {READ:04X}", "run", *commands, "regs", "quit"])
                   + "\n").encode(), capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertNotIn(b"Cycle limit reached", result.stderr)
        registers = re.findall(rb"PC=([0-9A-F]{4}).*? SP=([0-9A-F]{2})", result.stderr)
        self.assertTrue(registers, result.stderr)
        self.assertEqual(registers[-1], (f"{READ:04X}".encode(), b"FD"))
        return result.stdout

    def scan_commands(self, responders):
        commands = [f"break {HIGH:04X}", "send 35 0D", "run"]
        for address in range(0x08, 0x78):
            # START, eight address bits, target ACK/NACK, STOP.
            levels = [0xC0] * 9 + [0x40 if address in responders else 0xC0, 0xC0]
            for level in levels:
                commands += [f"write B000 {level:02X}", "run"]
        commands += [f"break delete {HIGH:04X}"]
        return commands

    def test_menu_scan_with_no_devices(self):
        output = self.run_menu(["send 35 0D", "run"])
        self.assertEqual(output.count(b"5. I2C SCAN\r\n"), 2)
        self.assertIn(b"I2C SCAN (7-BIT $08-$77)\r\nNO I2C DEVICES FOUND\r\n", output)
        self.assertNotIn(b"FOUND $", output)
        self.assertNotIn(b"FAILED", output)

    def test_scan_reports_addresses_and_resets_count_on_next_scan(self):
        responders = {0x08, 0x3C, 0x68, 0x77}
        output = self.run_menu(self.scan_commands(responders) + self.scan_commands(set()),
                               simulated=True)
        self.assertIn(b"FOUND $08\r\nFOUND $3C\r\nFOUND $68\r\nFOUND $77\r\n"
                      b"I2C SCAN COMPLETE\r\n", output)
        self.assertEqual(output.count(b"FOUND $"), 4)
        self.assertEqual(output.count(b"NO I2C DEVICES FOUND\r\n"), 1)
        self.assertEqual(output.count(b"SYSTEM DIAGNOSTICS\r\n"), 3)

    def test_stuck_clock_reports_error_and_returns_to_menu(self):
        # RAM-backed SCL remains low after initialization.
        output = self.run_menu(["send 35 0D", "run"], simulated=True)
        self.assertIn(b"I2C SCAN FAILED: SCL TIMEOUT\r\n", output)
        self.assertNotIn(b"NO I2C DEVICES FOUND", output)
        self.assertNotIn(b"I2C SCAN COMPLETE", output)
        self.assertEqual(output.count(b"SYSTEM DIAGNOSTICS\r\n"), 2)

    def test_existing_option_and_invalid_selection(self):
        # Invalid selections re-prompt; option 3 still selects the ACIA placeholder.
        output = self.run_menu(["send 36 0D", "run", "send 33 0D", "run"])
        self.assertIn(b"INVALID SELECTION\r\n", output)
        self.assertIn(b"option 3\r\n", output)
        self.assertNotIn(b"I2C SCAN (7-BIT", output)


if __name__ == "__main__":
    unittest.main()
