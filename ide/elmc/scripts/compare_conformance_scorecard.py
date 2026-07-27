#!/usr/bin/env python3

import argparse
import json
from pathlib import Path
from typing import Dict, Tuple


def read_json(path: Path) -> Dict:
    return json.loads(path.read_text(encoding="utf-8"))


def metric_pair(doc: Dict, key: str) -> Tuple[int, int]:
    node = doc.get(key, {})
    total = int(node.get("total", 0))
    present = int(node.get("present", total))
    return total, present


def metric_single(doc: Dict, key: str) -> int:
    node = doc.get(key, {})
    return int(node.get("total", 0))


def main() -> None:
    parser = argparse.ArgumentParser(description="Compare conformance scorecard to baseline.")
    parser.add_argument("--baseline", required=True, help="Path to baseline json.")
    parser.add_argument("--current", required=True, help="Path to current scorecard json.")
    parser.add_argument("--out", required=True, help="Path to markdown output report.")
    args = parser.parse_args()

    baseline_path = Path(args.baseline)
    current_path = Path(args.current)
    out_path = Path(args.out)

    baseline = read_json(baseline_path)
    current = read_json(current_path)

    checks = []

    for key in ("required_functions", "required_runtime_symbols"):
        b_total, b_present = metric_pair(baseline, key)
        c_total, c_present = metric_pair(current, key)
        checks.append(
            {
                "name": key,
                "baseline": f"{b_present}/{b_total}",
                "current": f"{c_present}/{c_total}",
                "pass": c_total >= b_total and c_present >= b_present,
                "delta_total": c_total - b_total,
                "delta_present": c_present - b_present,
            }
        )

    b_behavior = metric_single(baseline, "behavior_assertions")
    c_behavior = metric_single(current, "behavior_assertions")
    checks.append(
        {
            "name": "behavior_assertions",
            "baseline": str(b_behavior),
            "current": str(c_behavior),
            "pass": c_behavior >= b_behavior,
            "delta_total": c_behavior - b_behavior,
            "delta_present": 0,
        }
    )

    failed = [c for c in checks if not c["pass"]]
    status = "PASS" if not failed else "FAIL"

    lines = [
        "# Conformance Guardrail Report",
        "",
        f"- Status: **{status}**",
        f"- Baseline: `{baseline_path}`",
        f"- Current: `{current_path}`",
        "",
        "## Metric Deltas",
    ]

    for c in checks:
        delta = c["delta_total"] if c["name"] == "behavior_assertions" else f"{c['delta_present']}/{c['delta_total']}"
        marker = "PASS" if c["pass"] else "FAIL"
        lines.append(
            f"- `{marker}` {c['name']}: baseline `{c['baseline']}` -> current `{c['current']}` (delta `{delta}`)"
        )

    lines.append("")
    if failed:
        lines.append("## Failures")
        for c in failed:
            lines.append(f"- {c['name']} regressed below baseline.")
        lines.append("")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"guardrail status: {status}")
    print(f"wrote report: {out_path}")

    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
