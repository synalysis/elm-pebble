#!/usr/bin/env python3
"""Remove stray alias lines appended after module end by inject-typespecs."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ALIAS_LINE = re.compile(r"^\s*alias\s+.+\s+as:\s+Types\s*$")


def fix_file(path: Path) -> int:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    # find last non-empty line index
    last = len(lines) - 1
    while last >= 0 and not lines[last].strip():
        last -= 1
    removed = 0
    while last >= 0 and ALIAS_LINE.match(lines[last]):
        removed += 1
        last -= 1
        while last >= 0 and not lines[last].strip():
            last -= 1
    if not removed:
        return 0
    new_lines = lines[: last + 1]
    path.chmod(path.stat().st_mode | 0o200)
    path.write_text("\n".join(new_lines) + "\n", encoding="utf-8")
    return removed


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    total = 0
    for pkg in ("elm_ex", "elmc", "elmx", "ide"):
        for path in (root / pkg / "lib").rglob("*.ex"):
            total += fix_file(path)
    print(f"removed {total} trailing alias lines")
    return 0


if __name__ == "__main__":
    sys.exit(main())
