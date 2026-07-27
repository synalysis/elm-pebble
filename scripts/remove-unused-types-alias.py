#!/usr/bin/env python3
"""Remove unused `alias ... as: Types` lines injected when no Types.* reference remains."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

PACKAGES = ("elm_ex", "elmc", "elmx", "ide")
ALIAS_RE = re.compile(r"^\s*alias\s+[\w.]+\s*,\s*as:\s*Types\s*$")


def clean_file(path: Path) -> int:
    text = path.read_text(encoding="utf-8")
    if "as: Types" not in text:
        return 0
    if re.search(r"(?<![\w.])Types\.[A-Za-z_]\w*\(", text) is None:
        lines = [ln for ln in text.splitlines() if not ALIAS_RE.match(ln)]
        if len(lines) != len(text.splitlines()):
            path.chmod(path.stat().st_mode | 0o200)
            path.write_text("\n".join(lines) + "\n", encoding="utf-8")
            return 1
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--package", choices=PACKAGES, action="append")
    args = parser.parse_args()
    total = 0
    for pkg in args.package or PACKAGES:
        for path in sorted((args.root / pkg / "lib").rglob("*.ex")):
            if "vendor" in path.parts:
                continue
            total += clean_file(path)
    print(f"removed unused Types alias from {total} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
