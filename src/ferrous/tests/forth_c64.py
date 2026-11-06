#!/usr/bin/env python3
"""After make forth: python3 tests/forth_c64.py PATH/TO/joshua."""
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest

EXECUTABLE = pathlib.Path(sys.argv.pop(1)).resolve()
ROOT = pathlib.Path(__file__).resolve().parents[1]
PROFILE = ROOT.parent / "joshua/profiles/forth.profile"
SOURCE = (ROOT / "forth.s").read_text()
ROM = (ROOT / "forth.bin").read_bytes()
LABELS = {}
for line in (ROOT / "forth.lbl").read_text().splitlines():
    _, address, name = line.split()
    LABELS[name.lstrip(".")] = int(address, 16)


def cell(address):
    return int.from_bytes(ROM[address - 0xC000:address - 0xC000 + 2], "little")


def stub_entries():
    """Resolve retained dictionary names to CFAs using the encoded name length."""
    entries = {}
    for block in re.split(r"(?=^; Dictionary: )", SOURCE, flags=re.M):
        if not block.startswith("; Dictionary: "):
            continue
        if "; IMNOTWOPR: unavailable;" not in block:
            continue
        name = re.match(r"; Dictionary: (.*?) \[([^]]+)\]", block)
        header = re.search(r"^(\w+):", block, re.M)[1]
        nfa = LABELS[header]
        cfa = nfa + 1 + (ROM[nfa - 0xC000] & 0x1F) + 2
        entries[(name[1], name[2])] = cfa
    return entries


class C64PortTests(unittest.TestCase):
    def run_monitor(self, commands):
        result = subprocess.run(
            [str(EXECUTABLE), "--profile", str(PROFILE),
             "--console-newline", "raw", "--cycles", "20000", "--unthrottled"],
            input=("\n".join(commands + ["quit"]) + "\n").encode(),
            capture_output=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        return result

    def test_rom_layout_and_error_table(self):
        self.assertEqual(len(ROM), 0x4000)
        self.assertEqual(cell(0xFFFC), LABELS["reset"])
        self.assertEqual(LABELS["ERR_NO_C64_SLOT"] - LABELS["L8FD2"], 26 * 2)
        self.assertEqual(cell(LABELS["ERR_NO_C64_SLOT"]), LABELS["ERR_NO_C64"])
        message = LABELS["ERR_NO_C64"] - 0xC000
        self.assertEqual(ROM[message:message + 7], b"\x06NO C64")
        # MESSAGE's CLIT bound must include the newly appended table entry.
        self.assertEqual(ROM[LABELS["MESS"] - 0xC000 + 4], 26)

    def test_all_retained_stubs_report_without_arguments_or_user_area(self):
        entries = stub_entries()
        # Cover direct hardware, KERNAL wrappers, storage, and high-level users.
        expected = {
            ("BORDER", "FORTH"), ("UPORT", "FORTH"), ("EM", "FORTH"),
            ("OPEN", "SYSTEM"), ("CHRIN", "SYSTEM"), ("SETNAM", "SYSTEM"),
            ("DISK", "FORTH"), ("FILE", "FORTH"), (">RAM", "SYSTEM"),
            ("S!", "FORTH"), ("VOICE1", "FORTH"), ("SPEDIT", "FORTH"),
            ("EDIT", "FORTH"), ("V", "EDITOR"), ("COLD", "FORTH"),
        }
        self.assertTrue(expected <= entries.keys())
        self.assertEqual(len(entries), 195)
        cfas = list(entries.values()) + [LABELS[name] for name in
                                        ("PKEY", "PQTER", "L964F", "PRSLW")]
        for cfa in cfas:
            self.assertEqual(cell(cfa), LABELS["NO_C64"], f"CFA ${cfa:04X}")

        with tempfile.TemporaryDirectory() as directory:
            canaries = pathlib.Path(directory, "canaries.bin")
            # Old C64 keyboard state remains untouched by every error trap.
            commands = ["write C5 " + " ".join(["A5"] * 16),
                        f"break {LABELS['main']:04X}"]
            for cfa in cfas:
                commands += [f"write 800 {cfa & 255:02X} {cfa >> 8:02X}",
                             "write 70 00 08", "regs x 60", "regs y 0",
                             f"run {LABELS['NEXT']:04X}"]
            commands += [f'save "{canaries}" C5 10']
            result = self.run_monitor(commands)
            self.assertEqual(result.stdout, b"NO C64\r\n" * len(cfas))
            self.assertEqual(canaries.read_bytes(), b"\xA5" * 16)

    def test_legacy_native_entries_and_restart_threads(self):
        commands = [f"break {LABELS['main']:04X}"]
        for name in ("L8009", "L8019", "L936B", "L9374"):
            commands += [f"run {LABELS[name]:04X}"]
        result = self.run_monitor(commands)
        self.assertEqual(result.stdout, b"NO C64\r\n" * 4)

    def test_no_active_c64_hardware_or_kernal_references(self):
        historical = SOURCE[:SOURCE.index("USRINI")]
        names = re.findall(r"^(\w+)\s*=", historical, re.M)
        references = re.compile(r"\b(?:" + "|".join(names) + r")\b")
        for number, line in enumerate(SOURCE.splitlines(), 1):
            if line.lstrip().startswith(";") or re.match(r"^\w+\s*=", line):
                continue
            self.assertIsNone(references.search(line.split(";", 1)[0]),
                              f"C64 reference on line {number}: {line}")


if __name__ == "__main__":
    unittest.main()
