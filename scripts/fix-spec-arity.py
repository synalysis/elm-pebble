#!/usr/bin/env python3
"""Remove invalid inject-generated @spec lines (junk patterns and arity mismatches)."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

PACKAGES = ("elm_ex", "elmc", "elmx", "ide")

DEF_START = re.compile(
    r"^(\s*)(def|defmacro|defmacrop|defp|defmacro)\s+([a-zA-Z_][\w!?]*)\s*"
)
SPEC_NAME = re.compile(r"^\s*@spec\s+([a-zA-Z_][\w!?]*)\s*\(")
INJECT_JUNK = re.compile(
    r"^\s*@spec\s+\w+\([^)]*Types\.expr\(\)\s*\|\s*Types\.expr\(\)[^)]*\)\s*::\s*Types\.expr\(\)\s*$"
)
INJECT_JUNK_ELMC = re.compile(
    r"^\s*@spec\s+\w+\([^)]*Types\.ir_expr\(\)\s*\|\s*Types\.ir_expr\(\)[^)]*\)\s*::\s*Types\.ir_expr\(\)\s*$"
)
META = frozenset({"@doc", "@moduledoc", "@impl", "@dialyzer", "@deprecated", "@since"})


def spec_arg_count(line: str) -> int | None:
    m = SPEC_NAME.match(line)
    if not m:
        return None
    start = line.index("(")
    depth = 0
    for i, ch in enumerate(line[start:], start):
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                inner = line[start + 1 : i].strip()
                if not inner:
                    return 0
                return inner.count(",") + 1
    return None


def count_def_args(lines: list[str], i: int) -> int | None:
    m = DEF_START.match(lines[i])
    if not m:
        return None
    rest = lines[i][m.end() :].strip()
    if not rest.startswith("("):
        return 0
    depth = 0
    buf: list[str] = []
    j = i
    while j < len(lines):
        col_start = m.end() if j == i else 0
        for ch in lines[j][col_start:]:
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0:
                    inner = "".join(buf).strip()
                    if not inner:
                        return 0
                    return inner.count(",") + 1
            if depth > 0:
                buf.append(ch)
        j += 1
    return None


def is_junk_spec(line: str, package: str) -> bool:
    if INJECT_JUNK.match(line):
        return True
    if package in ("elmc", "elmx") and INJECT_JUNK_ELMC.match(line):
        return True
    return False


def fix_file(path: Path, package: str) -> int:
    lines = path.read_text(encoding="utf-8").splitlines()
    remove: set[int] = set()
    i = 0
    while i < len(lines):
        line = lines[i]
        if not line.strip().startswith("@spec"):
            i += 1
            continue

        if is_junk_spec(line, package):
            remove.add(i)
            i += 1
            continue

        spec_arity = spec_arg_count(line)
        spec_name = SPEC_NAME.match(line)
        j = i + 1
        while j < len(lines):
            s = lines[j].strip()
            if not s or any(s.startswith(m) for m in META) or s.startswith("#"):
                j += 1
                continue
            if DEF_START.match(lines[j]):
                def_m = DEF_START.match(lines[j])
                def_arity = count_def_args(lines, j)
                if (
                    spec_arity is not None
                    and def_arity is not None
                    and spec_name
                    and def_m
                    and spec_name.group(1) == def_m.group(3)
                    and spec_arity != def_arity
                    and "Types.expr() | Types.expr()" in line
                ):
                    remove.add(i)
                break
            break
        i += 1

    if not remove:
        return 0
    new_lines = [ln for idx, ln in enumerate(lines) if idx not in remove]
    path.write_text("\n".join(new_lines) + "\n", encoding="utf-8")
    return len(remove)


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
            total += fix_file(path, pkg)
    print(f"removed {total} invalid spec lines")
    return 0


if __name__ == "__main__":
    sys.exit(main())
