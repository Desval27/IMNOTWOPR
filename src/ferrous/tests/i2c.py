#!/usr/bin/env python3
"""CPU-level I2C regressions using Joshua's monitor and the linked ROM.

Run after `make -C src/ferrous all`:
    python3 src/ferrous/tests/i2c.py src/joshua/build/gcc14/joshua -v

VIA registers are backed by RAM here so tests can inject pin levels at each
clock release. This checks firmware control flow, stack balance and transfer
contents, not VIA electrical behavior, pull-ups or physical bus timing.
"""
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest

EXECUTABLE = pathlib.Path(sys.argv.pop(1)).resolve()
ROOT = pathlib.Path(__file__).resolve().parents[1]
LABELS = {}
for line in (ROOT / "ferrous.lbl").read_text().splitlines():
    _, address, name = line.split()
    LABELS[name.lstrip(".")] = int(address, 16)
HIGH = LABELS["i2c_scl_high"]
REGISTERS = re.compile(
    r"PC=([0-9A-F]{4}) A=([0-9A-F]{2}) X=([0-9A-F]{2}) "
    r"Y=([0-9A-F]{2}) SP=([0-9A-F]{2}) P=([0-9A-F]{2})")


def write(address, values):
    return f"write {address:04X} " + " ".join(f"{v:02X}" for v in values)


class I2cTests(unittest.TestCase):
    def run_routine(self, name, *, a=0, x=0x55, y=0x37, p=0x24,
                    setup=(), clocks=None, pin=0x40, timeout_at=None, stretch=False):
        address = LABELS[name]
        commands = [f'load "{ROOT / "ferrous.bin"}" C000',
                    write(0x0200, [0x20, address & 255, address >> 8, 0xEA]),
                    write(0xB000, [pin, 0, 0x40]),
                    f"regs a {a:02X}", f"regs x {x:02X}",
                    f"regs y {y:02X}", f"regs p {p:02X}",
                    "regs sp FC", "break 0203", *setup]
        if clocks is not None:
            commands += [f"break {HIGH:04X}", "run 0200"]
            for index, level in enumerate(clocks):
                # DDR at clock release records the controller's SDA bit.
                commands += ["mem B002 L 1"]
                if stretch:
                    commands += [write(0xB000, [0]), "step 20", "mem B002 L 1"]
                commands += [write(0xB000, [level])]
                if index == timeout_at:
                    # Also let cleanup STOP execute against the stuck-low pin.
                    commands += [f"break delete {HIGH:04X}", "run"]
                    break
                commands += ["run"]
        else:
            commands += ["run 0200"]
        commands += ["regs", "mem 03FF L 10", "mem B000 L C", "quit"]
        result = subprocess.run(
            [str(EXECUTABLE), "--ram", "0:10000", "--rom", "none",
             "--via", "none", "--acia", "none", "--cycles", "1000000",
             "--unthrottled"], input="\n".join(commands) + "\n",
            text=True, capture_output=True, timeout=30)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertNotIn("Cycle limit reached", output)
        matches = REGISTERS.findall(output)
        self.assertTrue(matches, output)
        registers = tuple(int(v, 16) for v in matches[-1])
        self.assertEqual(registers[0], 0x0203, output)
        self.assertEqual(registers[4], 0xFC, "Unbalanced hardware stack")
        self.assertEqual(registers[5] & 0x0C, p & 0x0C,
                         "Interrupt or decimal mode changed")
        ddr = [int(v, 16) for v in re.findall(r"B002  ([0-9A-F]{2})", output)]
        def memory(address):
            match = re.search(rf"{address:04X}  ((?:[0-9A-F]{{2}} )+)", output)
            return bytes.fromhex(match[1])
        return registers, ddr, memory(0x03FF), memory(0xB000)

    def transfer(self, length):
        return [write(LABELS["i2c_ptr"], [0, 4]),
                write(LABELS["i2c_len"], [length]),
                write(LABELS["i2c_addr"], [0x68]),
                write(LABELS["i2c_reg"], [0x12]),
                write(0x03FF, [0xAA] * 16)]

    def test_init_preserves_unrelated_bits(self):
        regs, _, _, via = self.run_routine("i2c_init", setup=[
            write(0xB000, [0xFF, 0, 0xF5]), write(0xB00B, [0xFF])])
        self.assertEqual(via[0], 0x3F)
        self.assertEqual(via[2], 0x35)
        self.assertEqual(via[11], 0x7D)
        self.assertEqual(regs[5] & 1, 0)

    def test_read_byte_data_ack_and_registers(self):
        for value in (0x00, 0xFF, 0xA5, 0x5A):
            for nack in (0, 1):
                with self.subTest(value=value, nack=nack):
                    pins = [0x40 | (((value >> bit) & 1) << 7)
                            for bit in range(7, -1, -1)] + [0xC0]
                    regs, ddr, _, via = self.run_routine(
                        "i2c_read_byte", p=0x2C | nack, clocks=pins)
                    self.assertEqual(regs[1:4], (value, 0x55, 0x37))
                    self.assertEqual(regs[5] & 1, 0)
                    self.assertEqual(ddr[-1] & 0x80, 0 if nack else 0x80)
                    self.assertEqual(via[2] & 0xC0, 0x40)

    def test_write_byte_bits_and_target_ack(self):
        for value in (0x00, 0xFF, 0xA5, 0x5A):
            for nack in (0, 1):
                with self.subTest(value=value, nack=nack):
                    regs, ddr, _, _ = self.run_routine(
                        "i2c_write_byte", a=value,
                        clocks=[0xC0] * 8 + [0x40 | (nack << 7)])
                    bits = [0 if v & 0x80 else 1 for v in ddr[:8]]
                    self.assertEqual(bits, [(value >> bit) & 1 for bit in range(7, -1, -1)])
                    self.assertEqual(ddr[-1] & 0x80, 0)
                    self.assertEqual(regs[3], 0x37)
                    self.assertEqual(regs[5] & 1, nack)

    def test_register_read_repeated_start_buffer_and_final_nack(self):
        expected = [0x59, 0x23, 0x12, 0x07, 0x31, 0x10, 0x26]
        # START, write address, register, repeated START, read address.
        pins = [0x40] * 29
        for value in expected:
            pins += [0x40 | (((value >> bit) & 1) << 7)
                     for bit in range(7, -1, -1)] + [0xC0]
        pins += [0xC0]  # STOP
        regs, ddr, memory, via = self.run_routine(
            "i2c_read_reg", setup=self.transfer(7), clocks=pins)
        self.assertEqual(regs[5] & 1, 0)
        self.assertEqual(memory[:9], bytes([0xAA, *expected, 0xAA]))
        self.assertEqual([ddr[29 + 9 * i + 8] & 0x80 for i in range(7)],
                         [0x80] * 6 + [0])
        for offset, value in ((1, 0xD0), (10, 0x12), (20, 0xD1)):
            self.assertEqual([0 if d & 0x80 else 1 for d in ddr[offset:offset + 8]],
                             [(value >> bit) & 1 for bit in range(7, -1, -1)])
        self.assertEqual(via[2] & 0xC0, 0)

    def test_register_write_contents(self):
        expected = [0xD0, 0x12, 0xA5, 0x5A]
        regs, ddr, _, via = self.run_routine(
            "i2c_write_reg", setup=self.transfer(2) + [write(0x0400, expected[2:])],
            clocks=[0x40] * (1 + 9 * len(expected) + 1))
        self.assertEqual(regs[5] & 1, 0)
        for i, value in enumerate(expected):
            offset = 1 + i * 9
            self.assertEqual([0 if d & 0x80 else 1 for d in ddr[offset:offset + 8]],
                             [(value >> bit) & 1 for bit in range(7, -1, -1)])
        self.assertEqual(via[2] & 0xC0, 0)

    def test_zero_lengths_do_not_touch_bus_or_buffer(self):
        for name in ("i2c_read_reg", "i2c_write_reg"):
            with self.subTest(name=name):
                regs, _, memory, via = self.run_routine(name, setup=self.transfer(0))
                self.assertEqual(regs[5] & 1, 1)
                self.assertEqual(memory, bytes([0xAA] * 16))
                self.assertEqual(via[2], 0x40)

    def test_timeouts_balance_stack_release_lines_and_propagate(self):
        # Inject a timeout at every clock release, including ACKs and STOP.
        for name, count in (("i2c_start", 1), ("i2c_stop", 1),
                            ("i2c_read_byte", 9), ("i2c_write_byte", 9),
                            ("i2c_read_reg", 39), ("i2c_write_reg", 29)):
            for clock in range(count):
                with self.subTest(name=name, clock=clock):
                    regs, _, _, via = self.run_routine(
                        name, setup=self.transfer(1),
                        clocks=[0x40] * clock + [0], timeout_at=clock)
                    self.assertEqual(regs[5] & 1, 1)
                    self.assertEqual(via[2] & 0xC0, 0)
                    if name == "i2c_read_byte":
                        self.assertEqual(regs[2:4], (0x55, 0x37))

    def test_register_nack_still_reports_error_after_stop(self):
        for name in ("i2c_read_reg", "i2c_write_reg"):
            with self.subTest(name=name):
                regs, _, memory, via = self.run_routine(
                    name, setup=self.transfer(7), pin=0xC0)
                self.assertEqual(regs[5] & 1, 1)
                self.assertEqual(memory, bytes([0xAA] * 16))
                self.assertEqual(via[2] & 0xC0, 0)

    def test_stretch_then_resume_on_every_clock(self):
        for name, count in (("i2c_read_reg", 39), ("i2c_write_reg", 29)):
            with self.subTest(name=name):
                regs, ddr, memory, via = self.run_routine(
                    name, setup=self.transfer(1), clocks=[0x40] * count, stretch=True)
                self.assertEqual(regs[5] & 1, 0)
                for before, during in zip(ddr[::2], ddr[1::2]):
                    self.assertEqual(during & 0x40, 0, "SCL must remain released while waiting")
                    self.assertEqual(during & 0x80, before & 0x80,
                                     "SDA changed before SCL rose")
                if name == "i2c_read_reg":
                    self.assertEqual(memory[:3], bytes([0xAA, 0, 0xAA]))
                self.assertEqual(via[2] & 0xC0, 0)

    def test_scanner_completion_and_timeout_cleanup(self):
        regs, ddr, _, via = self.run_routine("i2c_scan_bus", x=0, clocks=[0xC0] * (112 * 11))
        self.assertEqual(regs[5] & 1, 0)
        self.assertEqual(len(ddr), 112 * 11)
        self.assertEqual(via[2] & 0xC0, 0)
        for clock in (0, 10):  # START, STOP (with saved probe flags on stack)
            with self.subTest(clock=clock):
                regs, _, _, via = self.run_routine(
                    "i2c_scan_bus", x=0, clocks=[0xC0] * clock + [0], timeout_at=clock)
                self.assertEqual(regs[5] & 1, 1)
                self.assertEqual(via[2] & 0xC0, 0)

    def test_scanner_callback_reports_only_acked_addresses(self):
        responders = {0x08, 0x3C, 0x68, 0x77}
        pins = []
        for address in range(0x08, 0x78):
            pins += [0xC0] * 9 + [0x40 if address in responders else 0xC0, 0xC0]
        # Callback logs A to a buffer, increments its count, and clobbers X/Y.
        callback = [0xAE, 0x00, 0x04, 0x9D, 0x01, 0x04, 0xEE, 0x00, 0x04,
                    0xA0, 0xEE, 0xA2, 0xDD, 0x60]
        regs, _, memory, _ = self.run_routine(
            "i2c_scan_bus", a=0, x=5, clocks=pins,
            setup=[write(0x0500, callback), write(0x0400, [0])])
        self.assertEqual(memory[1:6], bytes([4, *sorted(responders)]))
        self.assertEqual(regs[3], 0x37)
        self.assertEqual(regs[5] & 1, 0)

    def test_scanner_null_callback_with_responding_devices(self):
        regs, _, _, _ = self.run_routine("i2c_scan_bus", x=0, clocks=[0x40] * (112 * 11))
        self.assertEqual(regs[3], 0x37)
        self.assertEqual(regs[5] & 1, 0)

    def test_public_exports_link_from_another_module(self):
        routines = ("i2c_init", "i2c_start", "i2c_stop", "i2c_write_byte",
                    "i2c_read_byte", "i2c_write_reg", "i2c_read_reg", "i2c_scan_bus")
        parameters = ("i2c_ptr", "i2c_len", "i2c_addr", "i2c_reg")
        source = (".import " + ",".join(routines) + "\n.importzp " + ",".join(parameters)
                  + '\n.segment "PROGRAM_CODE"\n.word ' + ",".join(routines)
                  + "\nlda (i2c_ptr),y\nlda i2c_len\nlda i2c_addr\nlda i2c_reg\n"
                  + '.segment "RODATA"\n.byte 0\n.segment "VECTORS"\n.word 0,0,0\n')
        with tempfile.TemporaryDirectory(prefix="i2c-exports-") as directory:
            folder = pathlib.Path(directory)
            asm, obj, binary = (folder / name for name in ("caller.s", "caller.o", "caller.bin"))
            asm.write_text(source)
            for command in (["ca65", "--cpu", "65C02", str(asm), "-o", str(obj)],
                            ["ld65", "-C", str(ROOT / "config.cfg"), "-o", str(binary),
                             str(obj), str(ROOT / "obj/kernal.o")]):
                result = subprocess.run(command, text=True, capture_output=True, timeout=15)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main()
