#!/usr/bin/env python3
"""Serial-shell and retained C64-word checks; build with make forth first.

Usage: python3 tests/forth_c64.py PATH/TO/joshua
"""
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest

EXECUTABLE = pathlib.Path(sys.argv.pop(1)).resolve()
ROOT = pathlib.Path(__file__).resolve().parents[1]
PROFILE = ROOT.parent / "joshua/profiles/forth.profile"
SOURCES = {path: path.read_text() for path in
           (ROOT / "forth.s", ROOT / "lib/forth_shell.inc", ROOT / "lib/forth_words.inc")}
ROM = (ROOT / "forth.bin").read_bytes()
LABELS = {}
for line in (ROOT / "forth.lbl").read_text().splitlines():
    _, address, name = line.split()
    LABELS[name.lstrip(".")] = int(address, 16)

BANNER = b"WHOPPING FORTH\r\n16-bit serial shell; Ctrl-C aborts.\r\n"
PROMPT = b"ok> "
WAIT = LABELS["serial_wait_key"]


def cell(address):
    if not 0xC000 <= address <= 0xFFFE:
        raise ValueError(f"cell outside ROM: ${address:04X}")
    return int.from_bytes(ROM[address - 0xC000:address - 0xC000 + 2], "little")


def dictionary_entries():
    """Return each documented word's CFA and whether it is marked unavailable."""
    entries = {}
    for source in SOURCES.values():
        for block in re.split(r"(?=^; Dictionary: )", source, flags=re.M):
            name = re.match(r"; Dictionary: (.*?) \[([^]]+)\]", block)
            if not name:
                continue
            header = re.search(r"^(\w+):", block, re.M)[1]
            nfa = LABELS[header]
            cfa = nfa + 1 + (ROM[nfa - 0xC000] & 0x1F) + 2
            key = name[1], name[2]
            if key in entries:
                raise ValueError(f"duplicate dictionary entry: {key}")
            entries[key] = cfa, "; IMNOTWOPR: unavailable;" in block
    return entries


def send(data):
    return "send " + " ".join(f"{byte:02X}" for byte in data)


def forth_line(line):
    return [send(line.encode("ascii") + b"\r"), "run"]


def direct_c64_accesses(source):
    """Find literal or numeric-equate accesses to C64 I/O and KERNAL calls.

    Comments, immediate values, threaded-code data and symbolic ROM routines
    are not native hardware accesses. This is a source guard, not a general
    assembler or a proof about addresses computed at runtime.
    """
    lines = [line.split(";", 1)[0].strip() for line in source.splitlines()]
    literal = r"\$[0-9a-fA-F]+|[0-9]+"

    def number(token):
        return int(token[1:], 16) if token.startswith("$") else int(token)

    equates = {}
    for line in lines:
        match = re.fullmatch(rf"(\w+)\s*=\s*({literal})", line)
        if match:
            equates[match[1]] = number(match[2])
    memory_ops = "lda|ldx|ldy|sta|stx|sty|stz|adc|sbc|and|ora|eor|cmp|cpx|cpy|bit|inc|dec|asl|lsr|rol|ror|trb|tsb"
    instruction = re.compile(
        rf"(?:(?:[\w@]+)?:\s*)?({memory_ops}|jsr|jmp)\s+"
        rf"({literal}|[A-Za-z_]\w*)(\s*,\s*[xy])?", re.I)
    violations = []
    for lineno, line in enumerate(lines, 1):
        match = instruction.fullmatch(line)
        if not match:
            continue
        opcode, operand, index = match.groups()
        address = number(operand) if re.fullmatch(literal, operand) else equates.get(operand)
        if address is None:
            continue
        if opcode.lower() in ("jsr", "jmp"):
            forbidden = 0xFF81 <= address <= 0xFFF3  # C64 KERNAL jump table.
        else:
            forbidden = 0xD000 <= address <= 0xDFFF or (address in (0, 1) and not index)
        if forbidden:
            violations.append((lineno, line))
    return violations


class ForthPortTests(unittest.TestCase):
    def run_monitor(self, commands, *, stops=None):
        result = subprocess.run(
            [str(EXECUTABLE), "--profile", str(PROFILE),
             "--console-newline", "raw", "--cycles", "1000000", "--unthrottled"],
            input=("\n".join(commands + ["quit"]) + "\n").encode(),
            capture_output=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        if stops is not None:
            self.assertNotIn(b"Cycle limit reached", result.stderr)
            self.assertEqual(result.stderr.count(f"Breakpoint at ${WAIT:04X}.".encode()), stops)
        return result

    def test_rom_layout_and_error_table(self):
        self.assertEqual(len(ROM), 0x4000)
        for vector, target in ((0xFFFA, "shell_nmi"), (0xFFFC, "reset"), (0xFFFE, "shell_irq")):
            self.assertEqual(cell(vector), LABELS[target])
        table, end = LABELS["ERROR_TABLE"], LABELS["ERROR_TABLE_END"]
        self.assertGreater(end, table)
        self.assertEqual((end - table) % 2, 0)
        count = (end - table) // 2
        self.assertLessEqual(count, 256)
        # Error 26 remains the unsupported-C64 error; newer errors follow it.
        self.assertEqual(LABELS["ERR_NO_C64_SLOT"] - table, 26 * 2)
        for index, name in enumerate(("ERR_NO_C64", "ERR_STACK_FULL", "ERR_RX_FULL",
                                      "ERR_RETURN_FULL", "ERR_BREAK", "ERR_DIV_ZERO", "ERR_LINE_LONG"), 26):
            self.assertEqual(cell(table + index * 2), LABELS[name])
        for index in range(count):
            message = cell(table + index * 2) - 0xC000
            self.assertTrue(0 <= message < len(ROM))
            length = ROM[message]
            self.assertGreater(length, 0)
            self.assertLessEqual(message + 1 + length, len(ROM))
        # Verify the operand's context as well as its derived value.
        self.assertEqual(cell(LABELS["MESS"] + 2), LABELS["CLIT"])
        self.assertEqual(ROM[LABELS["MESS"] - 0xC000 + 4], count - 1)

    def test_message_bounds_and_new_errors(self):
        count = (LABELS["ERROR_TABLE_END"] - LABELS["ERROR_TABLE"]) // 2
        commands = ["run"]
        expected = BANNER + PROMPT
        # Exercise MESSAGE through the real interpreter, including both clamps.
        for value in (-1, 26, *range(27, count), count + 100):
            line = f"{value} MESSAGE CR"
            commands += forth_line(line)
            pointer = cell(LABELS["ERROR_TABLE"] + min(max(value, 0), count - 1) * 2) - 0xC000
            message = ROM[pointer + 1:pointer + 1 + ROM[pointer]]
            expected += line.encode() + b"\r\n" + message + b"\r\n\r\n" + PROMPT
        self.assertEqual(self.run_monitor(commands).stdout, expected)

    def test_all_retained_stubs_report_and_recover(self):
        entries = dictionary_entries()
        stubs = {key: cfa for key, (cfa, unavailable) in entries.items() if unavailable}
        expected = {
            ("BORDER", "FORTH"), ("UPORT", "FORTH"),
            ("OPEN", "SYSTEM"), ("CHRIN", "SYSTEM"), ("SETNAM", "SYSTEM"),
            ("DISK", "FORTH"), ("FILE", "FORTH"), (">RAM", "SYSTEM"),
            ("S!", "FORTH"), ("VOICE1", "FORTH"), ("SPEDIT", "FORTH"),
            ("EDIT", "FORTH"), ("V", "EDITOR"),
        }
        self.assertTrue(expected <= stubs.keys())
        # Check classification in both directions instead of freezing a stub count.
        self.assertEqual(set(stubs), {key for key, (cfa, _) in entries.items()
                                     if cell(cfa) == LABELS["NO_C64"]})
        for name in ("COLD", "ABORT", "EMPTY", "EM", "KEY", "?TERMINAL", "EMIT"):
            self.assertNotIn((name, "FORTH"), stubs)
        cfas = list(stubs.values()) + [LABELS["PRSLW"]]
        self.assertEqual(cell(LABELS["PRSLW"]), LABELS["NO_C64"])

        with tempfile.TemporaryDirectory() as directory:
            canaries = pathlib.Path(directory, "canaries.bin")
            # Initialize the board/serial hardware, then invoke every retained
            # stub with an empty stack and invalid UP. Recovery must restore UP
            # and return to the real input loop without touching C64 keyboard RAM.
            commands = [f"break {WAIT:04X}", "run", "write C5 " + " ".join(["A5"] * 16)]
            for cfa in cfas:
                commands += [f"write 800 {cfa & 255:02X} {cfa >> 8:02X}",
                             "write 70 00 08", "write 75 00 00", "regs x 60", "regs y 0",
                             f"run {LABELS['NEXT']:04X}"]
            commands += [f'save "{canaries}" C5 10', f"break delete {WAIT:04X}"]
            commands += forth_line("2 3 + .")
            result = self.run_monitor(commands)
            self.assertEqual(result.stderr.count(f"Breakpoint at ${WAIT:04X}.".encode()), len(cfas) + 1)
            self.assertEqual(result.stdout, BANNER + PROMPT + b"\r\n? NO C64\r\nok> " * len(cfas)
                             + b"2 3 + .\r\n5 \r\nok> ")
            self.assertEqual(canaries.read_bytes(), b"\xA5" * 16)

    def test_cold_entry_points_boot_the_shell(self):
        for name in ("reset", "COLD_BOOT", "COLD_THREAD_ENTRY"):
            with self.subTest(entry=name):
                result = self.run_monitor([f"break {WAIT:04X}", f"run {LABELS[name]:04X}"], stops=1)
                self.assertEqual(result.stdout, BANNER + PROMPT)

    def test_warm_preserves_definitions_and_cold_clears_them(self):
        for name, cold in (("WARM_BOOT", False), ("WARM_THREAD_ENTRY", False),
                           ("COLD_BOOT", True), ("COLD_THREAD_ENTRY", True)):
            with self.subTest(entry=name):
                commands = ["run"] + forth_line(": KEEP 73 ;") + [f"run {LABELS[name]:04X}"]
                commands += forth_line("KEEP .") + forth_line("2 3 + .")
                expected = BANNER + PROMPT + b": KEEP 73 ;\r\n\r\nok> "
                expected += (BANNER if cold else b"") + PROMPT + b"KEEP .\r\n"
                expected += b"\r\n? WHAT\r\nok> " if cold else b"73 \r\nok> "
                expected += b"2 3 + .\r\n5 \r\nok> "
                self.assertEqual(self.run_monitor(commands).stdout, expected)

    def test_serial_key_terminal_and_emit(self):
        commands = ["run"] + forth_line("?TERMINAL .") + forth_line("KEY EMIT")
        # KEY must block until another byte arrives; it must not report NO C64.
        commands += [send(b"Z"), "run"] + forth_line("65 EMIT")
        result = self.run_monitor(commands)
        self.assertEqual(result.stdout, BANNER + PROMPT + b"?TERMINAL .\r\n0 \r\nok> "
                         + b"KEY EMIT\r\nZ\r\nok> 65 EMIT\r\nA\r\nok> ")

    def test_board_io_mapping(self):
        for name, address in (("via_portb", 0xB000), ("acia_data", 0xB010),
                              ("acia_status", 0xB011), ("acia_cmd", 0xB012), ("acia_ctrl", 0xB013)):
            self.assertEqual(LABELS[name], address)

    def test_no_direct_c64_io_or_kernal_calls(self):
        # Keep the guard meaningful even after historical equate declarations
        # disappear. Indexed zero-page accesses are the Forth data stack.
        self.assertEqual(direct_c64_accesses(".import acia_data\nlda #$D020\n.word $FFD2\n"
                                            "lda 0,x\nsta acia_data\n; jsr $FFD2"), [])
        for instruction in ("sta $D020", "lda $DC00,x", "sta $01", "jsr $FFD2",
                            "jmp 65490", "BORDER = $D020\nsta BORDER"):
            with self.subTest(instruction=instruction):
                self.assertTrue(direct_c64_accesses(instruction))
        for path, source in SOURCES.items():
            self.assertEqual(direct_c64_accesses(source), [], str(path))


if __name__ == "__main__":
    unittest.main()
