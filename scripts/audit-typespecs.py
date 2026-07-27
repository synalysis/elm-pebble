#!/usr/bin/env python3
"""Audit @spec coverage and broad types in Elixir lib/ trees."""

from __future__ import annotations

import argparse
import os
import re
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

PACKAGES = ("elm_ex", "elmc", "elmx", "ide")

# @type definitions that intentionally use broad primitives.
ALLOWLIST_BROAD = {
    ("elmx/lib/elmx/types.ex", "elm_value"),
    ("elmx/lib/elmx/types.ex", "registry_args"),
}

META_ATTRS = frozenset(
    {
        "@doc",
        "@moduledoc",
        "@impl",
        "@dialyzer",
        "@deprecated",
        "@since",
        "@behaviour",
        "@before_compile",
    }
)

DEF_START = re.compile(
    r"^(\s*)(def|defmacro|defmacrop|defp|defmacro)\s+([a-zA-Z_][\w!?]*)\s*"
)
DEF_RE = re.compile(
    r"^(\s*)(def|defmacro|defmacrop|defp|defmacro)\s+([a-zA-Z_][\w!?]*)\s*(?:\(([^)]*)\)|\s*(?:do|,|\\|\s*$))",
)
SPEC_RE = re.compile(r"^\s*@spec\s+")
BROAD_RE = re.compile(r"\b(any\(\)|term\(\)|map\(\)|list\(\))\b")


@dataclass
class FunctionRow:
    package: str
    path: str
    kind: str
    name: str
    line: int
    has_spec: bool
    spec_text: str | None = None


@dataclass
class PackageReport:
    package: str
    total_defs: int = 0
    with_spec: int = 0
    missing: list[FunctionRow] = field(default_factory=list)
    broad: list[tuple[str, str, str, int]] = field(default_factory=list)
    files_with_defs: int = 0
    files_missing_any: int = 0


def is_meta_line(stripped: str) -> bool:
    if not stripped or stripped.startswith("#"):
        return True
    if stripped.startswith('"""') or stripped.startswith("'''"):
        return True
    return any(stripped.startswith(attr) for attr in META_ATTRS)


def collect_spec(lines: list[str], start: int) -> tuple[str, int]:
    chunk = [lines[start].rstrip()]
    i = start + 1
    while i < len(lines):
        s = lines[i].strip()
        if not s:
            i += 1
            continue
        if s.startswith("@") or DEF_START.match(lines[i]):
            break
        if s.startswith("|") or "::" in s or s.startswith("when"):
            chunk.append(lines[i].rstrip())
            i += 1
            continue
        if lines[i].startswith(" ") and not lines[i].startswith("  @"):
            chunk.append(lines[i].rstrip())
            i += 1
            continue
        break
    return " ".join(chunk), i


def find_spec_before(lines: list[str], def_line: int) -> str | None:
    j = def_line - 1
    while j >= 0:
        stripped = lines[j].strip()
        if is_meta_line(stripped):
            j -= 1
            continue
        if stripped.startswith("@spec"):
            spec, _ = collect_spec(lines, j)
            return spec
        # Multiline @spec return/continuation sitting above the def
        if (
            stripped.startswith("|")
            or stripped.startswith("when ")
            or (stripped.startswith("{") and j > 0 and "@spec" in lines[j - 1])
            or (
                j > 0
                and lines[j - 1].strip().startswith("@spec")
                and lines[j - 1].rstrip().endswith("::")
            )
        ):
            j -= 1
            continue
        return None
    return None


def find_spec_for_function(lines: list[str], line_idx: int, name: str) -> str | None:
    spec = find_spec_before(lines, line_idx)
    if spec and f"{name}(" in spec:
        return spec
    j = line_idx - 1
    while j >= 0:
        stripped = lines[j].strip()
        if stripped.startswith(f"@spec {name}("):
            spec, _ = collect_spec(lines, j)
            return spec
        if DEF_START.match(lines[j]):
            break
        j -= 1
    return spec


def is_types_only_module(text: str) -> bool:
    if "@type " not in text and "@opaque " not in text:
        return False
    return not DEF_START.search(text)


def parse_def_end_line(lines: list[str], i: int) -> int:
    m = DEF_START.match(lines[i])
    if not m:
        return i
    rest = lines[i][m.end() :].strip()
    if rest.startswith("(") or rest.startswith("%{") or rest.startswith("<<"):
        depth_paren = 0
        depth_brace = 0
        depth_bin = 0
        in_string = None
        started = False
        j = i
        while j < len(lines):
            col_start = m.end() if j == i else 0
            chunk = lines[j][col_start:]
            k = 0
            while k < len(chunk):
                if in_string is not None:
                    if chunk[k] == "\\" and k + 1 < len(chunk):
                        k += 2
                        continue
                    if chunk[k] == in_string:
                        in_string = None
                    k += 1
                    continue
                if chunk[k] == "?" and k + 1 < len(chunk):
                    prev = chunk[k - 1] if k > 0 else ""
                    if not (prev.isalnum() or prev == "_"):
                        k += 2
                        continue
                if chunk.startswith("<<", k):
                    depth_bin += 1
                    started = True
                    k += 2
                    continue
                if chunk.startswith(">>", k) and depth_bin > 0:
                    depth_bin -= 1
                    k += 2
                    if started and depth_paren <= 0 and depth_brace <= 0 and depth_bin <= 0:
                        return j
                    continue
                ch = chunk[k]
                if depth_bin == 0 and ch in ('"', "'"):
                    in_string = ch
                    k += 1
                    continue
                if depth_bin > 0:
                    k += 1
                    continue
                if ch == "(":
                    depth_paren += 1
                    started = True
                elif ch == ")":
                    depth_paren -= 1
                elif ch == "{":
                    depth_brace += 1
                    started = True
                elif ch == "}":
                    depth_brace -= 1
                if (
                    started
                    and depth_paren <= 0
                    and depth_brace <= 0
                    and depth_bin <= 0
                    and ch in ")}"
                ):
                    return j
                k += 1
            j += 1
        return i
    return i


def audit_file(package: str, path: Path) -> tuple[list[FunctionRow], list[tuple[str, str, str, int]]]:
    rel = str(path)
    try:
        text = path.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return [], []

    if is_types_only_module(text):
        return [], []

    lines = text.splitlines()
    rows: list[FunctionRow] = []
    broad: list[tuple[str, str, str, int]] = []
    groups: dict[tuple[str, str], FunctionRow] = {}

    i = 0
    while i < len(lines):
        m = DEF_START.match(lines[i])
        if m:
            kind, name = m.group(2), m.group(3)
            if name == "unquote":
                i = parse_def_end_line(lines, i) + 1
                continue
            key = (kind, name)
            spec = find_spec_for_function(lines, i, name)
            if key not in groups:
                groups[key] = FunctionRow(
                    package=package,
                    path=rel,
                    kind=kind,
                    name=name,
                    line=i + 1,
                    has_spec=spec is not None,
                    spec_text=spec,
                )
            else:
                if spec:
                    groups[key].has_spec = True
                    groups[key].spec_text = spec
                if i + 1 < groups[key].line:
                    groups[key].line = i + 1
            i = parse_def_end_line(lines, i) + 1
            continue
        if SPEC_RE.match(lines[i]):
            spec, next_i = collect_spec(lines, i)
            if BROAD_RE.search(spec):
                broad.append((rel, "<spec>", spec, i + 1))
            i = next_i
            continue
        i += 1

    for row in groups.values():
        rows.append(row)
        if row.spec_text and BROAD_RE.search(row.spec_text):
            allow = (rel, row.name)
            if allow not in ALLOWLIST_BROAD:
                broad.append((rel, row.name, row.spec_text, row.line))

    return rows, broad


def audit_package(root: Path, package: str) -> PackageReport:
    lib = root / package / "lib"
    report = PackageReport(package=package)
    if not lib.is_dir():
        return report

    by_file: dict[str, list[FunctionRow]] = defaultdict(list)
    for path in sorted(lib.rglob("*.ex")):
        if "vendor" in path.parts:
            continue
        rows, broad = audit_file(package, path)
        if rows:
            report.files_with_defs += 1
            by_file[str(path)] = rows
            report.total_defs += len(rows)
            for row in rows:
                if row.has_spec:
                    report.with_spec += 1
                else:
                    report.missing.append(row)
            if any(not r.has_spec for r in rows):
                report.files_missing_any += 1
        report.broad.extend(broad)

    return report


def print_summary(reports: list[PackageReport]) -> int:
    total_defs = sum(r.total_defs for r in reports)
    total_missing = sum(len(r.missing) for r in reports)
    total_broad = sum(len(r.broad) for r in reports)

    print("Typespec audit summary")
    print("=" * 72)
    for r in reports:
        pct = (100.0 * r.with_spec / r.total_defs) if r.total_defs else 100.0
        print(
            f"{r.package:8s}  defs={r.total_defs:5d}  specs={r.with_spec:5d}  "
            f"missing={len(r.missing):5d}  broad={len(r.broad):4d}  coverage={pct:5.1f}%"
        )
    print("-" * 72)
    print(
        f"{'TOTAL':8s}  defs={total_defs:5d}  missing={total_missing:5d}  broad={total_broad:4d}"
    )
    return total_missing + total_broad


def print_details(reports: list[PackageReport], kind: str, limit: int) -> None:
    for r in reports:
        if kind == "missing" and r.missing:
            by_file: dict[str, int] = defaultdict(int)
            for row in r.missing:
                by_file[row.path] += 1
            print(f"\n{r.package} — top files missing @spec:")
            for path, count in sorted(by_file.items(), key=lambda x: -x[1])[:limit]:
                print(f"  {count:4d}  {path}")
        if kind == "broad" and r.broad:
            print(f"\n{r.package} — broad @spec (first {limit}):")
            for path, name, spec, line in r.broad[:limit]:
                print(f"  {path}:{line}  {name}  {spec[:100]}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="Repo root",
    )
    parser.add_argument(
        "--package",
        action="append",
        choices=PACKAGES,
        help="Limit to package(s); default all",
    )
    parser.add_argument(
        "--details",
        choices=("missing", "broad", "both"),
        help="Print per-file detail",
    )
    parser.add_argument("--limit", type=int, default=20, help="Detail list limit")
    parser.add_argument(
        "--fail-on-gaps",
        action="store_true",
        help="Exit 1 if any missing or broad specs remain",
    )
    args = parser.parse_args()

    packages = args.package or list(PACKAGES)
    reports = [audit_package(args.root, pkg) for pkg in packages]
    exit_code = print_summary(reports)

    if args.details == "missing":
        print_details(reports, "missing", args.limit)
    elif args.details == "broad":
        print_details(reports, "broad", args.limit)
    elif args.details == "both":
        print_details(reports, "missing", args.limit)
        print_details(reports, "broad", args.limit)

    if args.fail_on_gaps and exit_code > 0:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
