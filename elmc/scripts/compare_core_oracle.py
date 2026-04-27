#!/usr/bin/env python3

import argparse
import json
import re
from pathlib import Path
from typing import Any, Dict, List, Tuple


ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
ELMC_TEST_RE = re.compile(r"\*\s+test\s+(.+?)\s+\(")
ELMC_SUMMARY_RE = re.compile(r"(\d+)\s+tests,\s+(\d+)\s+failures")


def read_text(path: Path) -> str:
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8", errors="replace")


def strip_ansi(text: str) -> str:
    return ANSI_RE.sub("", text).replace("\r", "\n")


def parse_elmc_log(text: str) -> Dict[str, Any]:
    clean = strip_ansi(text)
    test_names: List[str] = []

    for line in clean.splitlines():
        match = ELMC_TEST_RE.search(line)
        if match:
            test_names.append(match.group(1).strip())

    # Preserve order while deduplicating
    seen = set()
    ordered_names: List[str] = []
    for name in test_names:
        if name not in seen:
            seen.add(name)
            ordered_names.append(name)

    summary_match = ELMC_SUMMARY_RE.search(clean)
    if summary_match:
        total = int(summary_match.group(1))
        failures = int(summary_match.group(2))
    else:
        total = len(ordered_names)
        failures = 0

    return {
        "tests": [{"name": name, "status": "pass"} for name in ordered_names],
        "summary": {"total": total, "failures": failures},
    }


def parse_json_lines(raw: str) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    for line in raw.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        try:
            item = json.loads(stripped)
        except json.JSONDecodeError:
            continue
        if isinstance(item, dict):
            out.append(item)
    return out


def collect_named_statuses(node: Any) -> List[Tuple[str, str]]:
    hits: List[Tuple[str, str]] = []

    def walk(value: Any) -> None:
        if isinstance(value, dict):
            name = value.get("name") or value.get("label") or value.get("description")
            status = value.get("status") or value.get("result") or value.get("outcome")
            if isinstance(name, str) and isinstance(status, str):
                normalized = status.lower()
                if normalized in {"pass", "passed", "ok", "fail", "failed"}:
                    hits.append((name.strip(), normalized))
            for child in value.values():
                walk(child)
        elif isinstance(value, list):
            for child in value:
                walk(child)

    walk(node)
    return hits


def parse_elm_report(raw: str) -> Dict[str, Any]:
    if not raw.strip():
        return {"tests": [], "summary": {"total": 0, "failures": 0}, "raw_format": "missing"}

    parsed_node: Any = None
    raw_format = "unknown"

    try:
        parsed_node = json.loads(raw)
        raw_format = "json"
    except json.JSONDecodeError:
        events = parse_json_lines(raw)
        if events:
            parsed_node = events
            raw_format = "jsonl"

    if parsed_node is None:
        return {"tests": [], "summary": {"total": 0, "failures": 0}, "raw_format": "unparsed"}

    pairs = collect_named_statuses(parsed_node)
    seen = set()
    tests: List[Dict[str, str]] = []
    for name, status in pairs:
        key = (name, status)
        if key in seen:
            continue
        seen.add(key)
        normalized = "pass" if status in {"pass", "passed", "ok"} else "fail"
        tests.append({"name": name, "status": normalized})

    failures = sum(1 for t in tests if t["status"] == "fail")
    return {
        "tests": tests,
        "summary": {"total": len(tests), "failures": failures},
        "raw_format": raw_format,
    }


def build_report(elm: Dict[str, Any], elmc: Dict[str, Any], notes: List[str]) -> str:
    elm_total = elm["summary"]["total"]
    elm_fail = elm["summary"]["failures"]
    elmc_total = elmc["summary"]["total"]
    elmc_fail = elmc["summary"]["failures"]

    lines: List[str] = []
    lines.append("# Core Oracle Differential Report")
    lines.append("")
    lines.append("## Summary")
    lines.append(f"- Official elm-test: `{elm_total}` tests, `{elm_fail}` failures")
    lines.append(f"- elmc core suite: `{elmc_total}` tests, `{elmc_fail}` failures")
    lines.append("")

    if notes:
        lines.append("## Notes")
        for note in notes:
            lines.append(f"- {note}")
        lines.append("")

    lines.append("## elmc Tests")
    if elmc["tests"]:
        for test in elmc["tests"]:
            lines.append(f"- `{test['status']}` {test['name']}")
    else:
        lines.append("- No elmc test details parsed from log.")
    lines.append("")

    lines.append("## elm-test Parsed Entries")
    if elm["tests"]:
        for test in elm["tests"][:50]:
            lines.append(f"- `{test['status']}` {test['name']}")
        if len(elm["tests"]) > 50:
            lines.append(f"- ... {len(elm['tests']) - 50} more entries")
    else:
        lines.append("- No elm-test entries parsed (missing/unparseable report or early run failure).")
    lines.append("")

    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description="Compare core oracle artifacts.")
    parser.add_argument("--elm-json", required=True, help="Path to elm-test JSON report.")
    parser.add_argument("--elmc-log", required=True, help="Path to elmc core test log.")
    parser.add_argument("--out", required=True, help="Path to markdown output.")
    args = parser.parse_args()

    elm_json_path = Path(args.elm_json)
    elmc_log_path = Path(args.elmc_log)
    out_path = Path(args.out)

    notes: List[str] = []

    elm_raw = read_text(elm_json_path)
    if not elm_json_path.exists():
        notes.append(f"elm-test report missing: `{elm_json_path}`")
    elif not elm_raw.strip():
        notes.append(f"elm-test report is empty: `{elm_json_path}`")

    elmc_raw = read_text(elmc_log_path)
    if not elmc_log_path.exists():
        notes.append(f"elmc log missing: `{elmc_log_path}`")
    elif not elmc_raw.strip():
        notes.append(f"elmc log is empty: `{elmc_log_path}`")

    elm = parse_elm_report(elm_raw)
    elmc = parse_elmc_log(elmc_raw)

    if elm.get("raw_format") in {"unparsed", "unknown"}:
        notes.append("elm-test report could not be parsed as JSON/JSONL.")

    report = build_report(elm, elmc, notes)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(report, encoding="utf-8")
    print(f"wrote report: {out_path}")


if __name__ == "__main__":
    main()
