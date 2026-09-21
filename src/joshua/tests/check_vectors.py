#!/usr/bin/env python3
"""Run locally downloaded SingleStepTests/65x02 wdc65c02/v1 JSON files.

Usage: python3 tests/check_vectors.py build/gcc14/joshua_vectors path/*.json
Test data is external, is never fetched by the build, and remains under its
upstream license. The runner checks registers, memory AND all bus cycles.
"""
import json
import pathlib
import subprocess
import sys


def state(data):
    result = [data[key] for key in ("pc", "a", "x", "y", "s", "p")]
    result += [len(data["ram"])]
    for pair in data["ram"]:
        result.extend(pair)
    return result


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    failed = False
    for filename in sys.argv[2:]:
        cases = json.loads(pathlib.Path(filename).read_text())
        rows = []
        for case in cases:
            row = [case["name"].replace(" ", "_")]
            row += state(case["initial"]) + state(case["final"])
            row += [len(case["cycles"])]
            for address, value, operation in case["cycles"]:
                row += [address, value, int(operation == "write")]
            rows.append(" ".join(map(str, row)))
        result = subprocess.run([sys.argv[1]], input="\n".join(rows), text=True, capture_output=True)
        print(pathlib.Path(filename).name + ": " + result.stdout.strip())
        if result.returncode:
            failed = True
            print(result.stderr, file=sys.stderr)
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
