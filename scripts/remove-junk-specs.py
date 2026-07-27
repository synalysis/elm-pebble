#!/usr/bin/env python3
"""Remove inject-generated junk @spec lines."""

from __future__ import annotations

import re
import sys
from pathlib import Path

PACKAGES = ("elm_ex", "elmc", "elmx", "ide")

JUNK_PATTERNS = [
    re.compile(
        r"^\s*@spec\s+\w+\([^)]*Types\.expr\(\)\s*\|\s*Types\.expr\(\)[^)]*\)\s*::\s*Types\.expr\(\)\s*$"
    ),
    re.compile(
        r"^\s*@spec\s+do_split_top_level\(Types\.expr\(\), Types\.expr\(\), term\(\)"
    ),
    re.compile(r"^\s*@spec\s+type_name\?\(Types\.expr\(\) \| String\.t\(\), Types\.expr\(\)\)"),
    re.compile(r"^\s*@spec compile\(Types\.expr\(\), \[Types\.ir_expr\(\)\], Types\.ir_expr\(\)\)"),
    re.compile(
        r"^\s*@spec compile\(Types\.expr\(\), \[Types\.ir_expr\(\)\], Types\.compile_env\(\), Types\.ir_expr\(\)\)"
    ),
    re.compile(
        r"^\s*@spec compile\(Types\.expr\(\), \[Types\.ir_expr\(\)\], Types\.compile_env\(\), Types\.ir_expr\(\), Types\.ir_expr\(\) \| integer\(\)\)"
    ),
    re.compile(r"^\s*@spec compile_cfg\(Types\.ir_expr\(\), \[Types\.ir_expr\(\)\], Types\.ir_expr\(\)\)"),
]


def fix_file(path: Path) -> int:
    lines = path.read_text(encoding="utf-8").splitlines()
    remove = {i for i, line in enumerate(lines) if any(p.search(line) for p in JUNK_PATTERNS)}
    if not remove:
        return 0
    new_lines = [ln for i, ln in enumerate(lines) if i not in remove]
    path.chmod(path.stat().st_mode | 0o200)
    path.write_text("\n".join(new_lines) + "\n", encoding="utf-8")
    return len(remove)


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    total = 0
    for pkg in PACKAGES:
        for path in sorted((root / pkg / "lib").rglob("*.ex")):
            if "vendor" not in path.parts:
                total += fix_file(path)
    print(f"removed {total} junk spec lines")
    return 0


if __name__ == "__main__":
    sys.exit(main())
