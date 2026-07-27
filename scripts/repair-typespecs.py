#!/usr/bin/env python3
"""Repair broken typespec substitutions from naive tighten pass."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

PACKAGES = ("elm_ex", "elmc", "elmx", "ide")

REPAIRS = [
    (re.compile(r"(\w+)_Types\.expr\(\)"), r"\1_map()"),
    (re.compile(r"(\w+)_\[Types\.expr\(\)\]"), r"\1_list()"),
    (re.compile(r"Types\.(\w+)_\[Types\.expr\(\)\]"), r"Types.\1_list()"),
    (re.compile(r"Types\.wire_Types\.expr\(\)"), r"Types.wire_map()"),
    (re.compile(r"CoreIRTypes\.wire_Types\.expr\(\)"), r"CoreIRTypes.wire_map()"),
    (re.compile(r"ImportEntry\.wire_Types\.expr\(\)"), r"ImportEntry.wire_map()"),
    (re.compile(r"CmdCall\.wire_Types\.expr\(\)"), r"CmdCall.wire_map()"),
    (re.compile(r"Types\.string_\[Types\.expr\(\)\]"), r"Types.string_list()"),
    (re.compile(r"Types\.param_\[Types\.expr\(\)\]"), r"Types.param_list()"),
    (re.compile(r"Types\.binding_Types\.expr\(\)"), r"Types.binding_map()"),
    (re.compile(r"FCC\.name_Types\.expr\(\)"), r"FCC.name_map()"),
    (re.compile(r"FCC\.field_types_Types\.expr\(\)"), r"FCC.field_types_map()"),
    (re.compile(r"DeadCode\.function_Types\.expr\(\)"), r"DeadCode.function_map()"),
    (re.compile(r"Lookup\.import_unqualified_Types\.expr\(\)"), r"Lookup.import_unqualified_map()"),
]

INJECT_JUNK = re.compile(
    r"^\s*@spec\s+\w+\([^)]*Types\.expr\(\)\s*\|\s*Types\.expr\(\)[^)]*\)\s*::\s*Types\.expr\(\)\s*$"
)
DEF_START = re.compile(r"^\s*(def|defp|defmacro|defmacrop)\s+")


def repair_specs(text: str) -> tuple[str, int]:
    changes = 0
    for pat, repl in REPAIRS:
        new, n = pat.subn(repl, text)
        if n:
            changes += n
            text = new

    lines = text.splitlines()
    out: list[str] = []
    i = 0
    removed = 0
    while i < len(lines):
        line = lines[i]
        if INJECT_JUNK.match(line):
            # drop inject duplicate if another @spec follows before def
            j = i + 1
            while j < len(lines) and lines[j].strip() == "":
                j += 1
            if j < len(lines) and (
                lines[j].strip().startswith("@spec") or DEF_START.match(lines[j])
            ):
                removed += 1
                i += 1
                continue
        out.append(line)
        i += 1

    return "\n".join(out) + ("\n" if text.endswith("\n") else ""), changes + removed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--package", choices=PACKAGES, action="append")
    args = parser.parse_args()

    packages = args.package or list(PACKAGES)
    total = 0
    for pkg in packages:
        lib = args.root / pkg / "lib"
        for path in sorted(lib.rglob("*.ex")):
            if "vendor" in path.parts:
                continue
            text = path.read_text(encoding="utf-8")
            new, n = repair_specs(text)
            if n:
                path.write_text(new, encoding="utf-8")
                total += n
    print(f"repaired {total} issues")
    return 0


if __name__ == "__main__":
    sys.exit(main())
