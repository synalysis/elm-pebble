#!/usr/bin/env bash
# Report elm_pebble_dev WASM transfer sizes + Node boot timings.
#
# Usage:
#   ./scripts/benchmark-elm-pebble-dev-wasm.sh [wasm-web-out-dir]
#
# Environment:
#   PAGE_HTML   — elm-pages index.html for pageDataFromJs (default: elm_pebble_dev/dist/index.html)
#   BUDGET_BR_KB — optional max total brotli for wasm+manifest+host (fail if above)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/elm_pebble_dev/dist/wasm-web}"
if [[ "$OUT" != /* ]]; then
  OUT="$ROOT/$OUT"
fi
PAGE_HTML="${PAGE_HTML:-$ROOT/elm_pebble_dev/dist/index.html}"

if [[ ! -f "$OUT/wasm/app.wasm" ]]; then
  echo "error: missing $OUT/wasm/app.wasm — run npm run build:wasm first" >&2
  exit 1
fi

python3 - <<PY
from pathlib import Path
import json, gzip, statistics

try:
    import brotli
except ImportError as exc:
    raise SystemExit("python brotli required") from exc

out = Path("$OUT")
page = Path("$PAGE_HTML")

def br_size(path: Path) -> int:
    br = path.with_name(path.name + ".br")
    if br.is_file():
        return br.stat().st_size
    return len(brotli.compress(path.read_bytes(), quality=11))

def gz_size(path: Path) -> int:
    return len(gzip.compress(path.read_bytes(), compresslevel=9))

rows = []
wasm = out / "wasm" / "app.wasm"
manifest = out / "wasm" / "elmc_wasm.manifest.json"
host_js = sorted((out / "host").glob("*.js"))

def add(label, path):
    if not path.is_file():
        return
    rows.append((label, path.stat().st_size, gz_size(path), br_size(path)))

add("app.wasm", wasm)
add("manifest.json", manifest)
for p in host_js:
    add(f"host/{p.name}", p)

print("=== transfer sizes ===")
print(f"{'asset':40s} {'raw':>10s} {'gzip':>10s} {'brotli':>10s}")
total_raw = total_gz = total_br = 0
for label, raw, gz, br in rows:
    print(f"{label:40s} {raw:10d} {gz:10d} {br:10d}")
    total_raw += raw
    total_gz += gz
    total_br += br
print(f"{'TOTAL':40s} {total_raw:10d} {total_gz:10d} {total_br:10d}")

manifest_data = json.loads(manifest.read_text())
print(
    "manifest: minified=",
    manifest_data.get("minified"),
    "closure_count=",
    manifest_data.get("closure_count") or len(manifest_data.get("closures") or []),
    "immortal_strings=",
    (
        len(manifest_data["immortal_strings"])
        if isinstance(manifest_data.get("immortal_strings"), (list, dict))
        else 0
    ),
    "imports=",
    len(manifest_data.get("imports") or []),
)

budget_kb = None
try:
    import os
    budget_kb = os.environ.get("BUDGET_BR_KB")
    budget_kb = int(budget_kb) if budget_kb else None
except Exception:
    budget_kb = None

if budget_kb is not None:
    total_kb = (total_br + 1023) // 1024
    print(f"budget: {total_kb} KiB brotli vs BUDGET_BR_KB={budget_kb}")
    if total_kb > budget_kb:
        raise SystemExit(f"FAIL: brotli total {total_kb} KiB exceeds budget {budget_kb} KiB")
    print("budget: OK")

# Emit a machine-readable summary for CI.
summary = {
    "total_raw": total_raw,
    "total_gzip": total_gz,
    "total_brotli": total_br,
    "assets": [{"name": n, "raw": r, "gzip": g, "brotli": b} for n, r, g, b in rows],
}
(out / "wasm" / "size_report.json").write_text(json.dumps(summary, indent=2) + "\n")
print(f"wrote {out / 'wasm' / 'size_report.json'}")

# Compare against the elm-pages JS client adjacent to wasm-web (../ from out).
site = out.parent if out.name == "wasm-web" else out.parent
js_files = sorted(site.glob("elm.*.js")) + sorted((site / "assets").glob("index-*.js"))
css_files = sorted((site / "assets").glob("index-*.css"))
if js_files:
    print("=== vs elm-pages JS (same dist/) ===")
    js_raw = js_gz = js_br = 0
    for p in js_files:
        raw = p.stat().st_size
        gz = gz_size(p)
        brv = br_size(p) if p.with_name(p.name + ".br").is_file() else len(brotli.compress(p.read_bytes(), quality=11))
        print(f"{'JS '+p.name:40s} {raw:10d} {gz:10d} {brv:10d}")
        js_raw += raw; js_gz += gz; js_br += brv
    css_br = 0
    for p in css_files:
        css_br += len(brotli.compress(p.read_bytes(), quality=11))
    print(f"{'JS scripts TOTAL':40s} {js_raw:10d} {js_gz:10d} {js_br:10d}")
    print(f"{'WASM stack TOTAL':40s} {total_raw:10d} {total_gz:10d} {total_br:10d}")
    if js_br:
        print(f"ratio WASM/JS scripts (brotli): {total_br/js_br:.2f}x")
        print(f"ratio WASM/(JS+CSS) (brotli): {total_br/(js_br+css_br):.2f}x  (css br≈{css_br})")
    summary["js_scripts_brotli"] = js_br
    summary["css_brotli"] = css_br
    summary["ratio_wasm_vs_js_scripts"] = round(total_br / js_br, 3) if js_br else None
    (out / "wasm" / "size_report.json").write_text(json.dumps(summary, indent=2) + "\n")
PY

node "$ROOT/elmc/test/support/benchmark_wasm_boot.mjs" "$OUT" "$PAGE_HTML"
