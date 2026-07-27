#!/usr/bin/env python3
"""Remove @spec lines that make `mix compile` fail with undefined function arity."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

PACKAGES = ("elm_ex", "elmc", "elmx", "ide")
ERR_RE = re.compile(r"error: spec for undefined function ([a-zA-Z_][\w!?]*)/(\d+)")
SPEC_RE = re.compile(r"^\s*@spec\s+([a-zA-Z_][\w!?]*)\(")


def write_ex_file(path: Path, content: str) -> None:
    path.chmod(path.stat().st_mode | 0o200)
    path.write_text(content, encoding="utf-8")


def collect_spec_block(lines: list[str], start: int) -> tuple[int, str]:
    end = start
    while end < len(lines):
        if "::" in lines[end]:
            break
        end += 1
    return end, "\n".join(lines[start : end + 1])


def remove_spec_for(lines: list[str], name: str, bad_arity: int) -> list[str] | None:
    remove: set[int] = set()
    i = 0
    while i < len(lines):
        if not lines[i].strip().startswith("@spec"):
            i += 1
            continue
        end, spec_text = collect_spec_block(lines, i)
        m = SPEC_RE.match(spec_text.splitlines()[0])
        if not m or m.group(1) != name:
            i = end + 1
            continue
        args_part = spec_text.split(") ::", 1)[0]
        inner = args_part[args_part.index("(") + 1 :].strip()
        arity = 0 if not inner else inner.count(",") + 1
        if arity == bad_arity:
            remove.update(range(i, end + 1))
        i = end + 1
    if not remove:
        return None
    return [ln for idx, ln in enumerate(lines) if idx not in remove]


def compile_errors(pkg: str, root: Path) -> list[tuple[str, str, int]]:
    proc = subprocess.run(
        ["mix", "compile"],
        cwd=root / pkg,
        capture_output=True,
        text=True,
    )
    out = proc.stdout + proc.stderr
    errors: list[tuple[str, str, int]] = []
    current_file: str | None = None
    for line in out.splitlines():
        mfile = re.search(r"(lib/[\w./-]+\.ex):(\d+)", line)
        if mfile:
            current_file = mfile.group(1)
        merr = ERR_RE.search(line)
        if merr and current_file:
            errors.append((current_file, merr.group(1), int(merr.group(2))))
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--package", choices=PACKAGES, action="append")
    parser.add_argument("--max-rounds", type=int, default=20)
    args = parser.parse_args()
    total = 0
    for pkg in args.package or PACKAGES:
        for _ in range(args.max_rounds):
            errors = compile_errors(pkg, args.root)
            if not errors:
                break
            changed = False
            for rel, name, arity in errors:
                path = args.root / pkg / rel
                if not path.exists():
                    continue
                lines = path.read_text(encoding="utf-8").splitlines()
                new_lines = remove_spec_for(lines, name, arity)
                if new_lines is not None:
                    write_ex_file(path, "\n".join(new_lines) + "\n")
                    total += 1
                    changed = True
            if not changed:
                break
    print(f"removed bad specs from {total} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
