#!/usr/bin/env python3
"""Remove @spec blocks whose arity/name do not match any def/defp in the same file."""

from __future__ import annotations

import argparse
import importlib.util
import re
import sys
from collections import defaultdict
from pathlib import Path

PACKAGES = ("elm_ex", "elmc", "elmx", "ide")


def write_ex_file(path: Path, content: str) -> None:
    path.chmod(path.stat().st_mode | 0o200)
    path.write_text(content, encoding="utf-8")

SPEC_START = re.compile(r"^\s*@spec\s+([a-zA-Z_][\w!?]*)\s*\(")


def load_inject():
    path = Path(__file__).resolve().parent / "inject-typespecs.py"
    spec = importlib.util.spec_from_file_location("inject_typespecs", path)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod


def spec_arg_count(spec_text: str) -> int | None:
    line = spec_text.splitlines()[0]
    m = SPEC_START.match(line)
    if not m:
        return None
    if ") ::" in spec_text:
        args_part = spec_text.split(") ::", 1)[0]
        inner = args_part[args_part.index("(") + 1 :].strip()
        if not inner:
            return 0
        return inner.count(",") + 1
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


def collect_spec_block(lines: list[str], start: int) -> tuple[int, str]:
    end = start
    chunk = [lines[start]]
    while end < len(lines):
        if "::" in lines[end]:
            break
        end += 1
        if end < len(lines):
            chunk.append(lines[end])
    return end, "\n".join(chunk)


def prune_file(path: Path, inject) -> int:
    lines = path.read_text(encoding="utf-8").splitlines()
    arities: dict[str, set[int]] = defaultdict(set)

    i = 0
    while i < len(lines):
        clause, nxt = inject.parse_def_clause(lines, i)
        if clause is None:
            i += 1
            continue
        arities[clause.name].add(len(clause.params))
        i = nxt

    remove: set[int] = set()
    seen_clause: set[str] = set()
    i = 0
    while i < len(lines):
        stripped = lines[i].strip()
        if stripped.startswith("@spec"):
            end, spec_text = collect_spec_block(lines, i)
            name_m = SPEC_START.match(spec_text.splitlines()[0])
            name = name_m.group(1) if name_m else None
            arity = spec_arg_count(spec_text)
            invalid = (
                name is None
                or arity is None
                or name not in arities
                or arity not in arities[name]
                or name in seen_clause
            )
            if invalid:
                remove.update(range(i, end + 1))
            i = end + 1
            continue

        clause, nxt = inject.parse_def_clause(lines, i)
        if clause is not None:
            seen_clause.add(clause.name)
            i = nxt
            continue
        i += 1

    if not remove:
        return 0
    new_lines = [ln for idx, ln in enumerate(lines) if idx not in remove]
    write_ex_file(path, "\n".join(new_lines) + "\n")
    return len(remove)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--package", choices=PACKAGES, action="append")
    args = parser.parse_args()
    inject = load_inject()
    total = 0
    for pkg in args.package or PACKAGES:
        for path in sorted((args.root / pkg / "lib").rglob("*.ex")):
            if "vendor" in path.parts:
                continue
            total += prune_file(path, inject)
    print(f"removed {total} invalid @spec lines")
    return 0


if __name__ == "__main__":
    sys.exit(main())
