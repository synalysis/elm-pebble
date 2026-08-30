#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/elm_pebble_dev"
OUT="${1:-$APP/dist/wasm-web}"
if [[ "$OUT" != /* ]]; then
  OUT="$ROOT/$OUT"
fi

KEEP_WAT="${KEEP_WAT:-0}"
SKIP_WASM_OPT="${SKIP_WASM_OPT:-0}"
SKIP_VERIFY="${SKIP_VERIFY:-0}"

# ELMC_FAST=1 — iterate without wasm-opt / probes; enables modest IR parallelism.
if [[ "${ELMC_FAST:-0}" == "1" || "${ELMC_FAST:-}" == "true" ]]; then
  SKIP_WASM_OPT="${SKIP_WASM_OPT:-1}"
  SKIP_VERIFY="${SKIP_VERIFY:-1}"
  export ELMC_FAST=1
  export ELMC_IR_PARALLEL="${ELMC_IR_PARALLEL:-2}"
  # Allow a second scheduler when IR lower runs in parallel (still ulimit-capped).
  export ELIXIR_ERL_OPTIONS="${ELIXIR_ERL_OPTIONS:-+S 2:2 +MMscs 512}"
fi

# ELMC_IR_PARALLEL>1 without FAST still bumps schedulers unless caller set ERL opts.
if [[ -n "${ELMC_IR_PARALLEL:-}" && "${ELMC_IR_PARALLEL}" -gt 1 ]]; then
  if [[ -z "${ELIXIR_ERL_OPTIONS:-}" || "${ELIXIR_ERL_OPTIONS}" == "+S 1:1 +MMscs 256" ]]; then
    export ELIXIR_ERL_OPTIONS="+S ${ELMC_IR_PARALLEL}:${ELMC_IR_PARALLEL} +MMscs 512"
  fi
fi

find_wasm_opt() {
  if [[ -n "${WASM_OPT:-}" && -x "${WASM_OPT}" ]]; then
    echo "$WASM_OPT"
    return 0
  fi
  if command -v wasm-opt >/dev/null 2>&1; then
    command -v wasm-opt
    return 0
  fi
  if [[ -x "$ROOT/tools/wasm-opt" ]]; then
    echo "$ROOT/tools/wasm-opt"
    return 0
  fi
  return 1
}

ensure_wasm_opt() {
  if find_wasm_opt >/dev/null; then
    find_wasm_opt
    return 0
  fi

  echo "==> fetching wasm-opt (binaryen) into tools/"
  mkdir -p "$ROOT/tools"
  local tmp
  tmp="$(mktemp -d)"
  # Pin to a known release; keep out of git (.gitignore tools/wasm-opt*).
  (cd "$tmp" && npm pack binaryen@130.0.0 >/dev/null && tar -xzf binaryen-*.tgz)
  cp "$tmp/package/bin/wasm-opt" "$ROOT/tools/wasm-opt"
  chmod +x "$ROOT/tools/wasm-opt"
  rm -rf "$tmp"
  echo "$ROOT/tools/wasm-opt"
}

# Guard the BEAM compile the same way as mix-test-limited / mix-run-limited.
# Full elmc recompile + wasm emit often needs more than 6 GiB virtual; 10 GiB
# matches mix-test-limited's default ceiling and still prevents unbounded OOM.
export TEST_ULIMIT_V_KB="${TEST_ULIMIT_V_KB:-10485760}"
export ELIXIR_ERL_OPTIONS="${ELIXIR_ERL_OPTIONS:-+S 1:1 +MMscs 256}"
if [[ "${ELMC_FAST:-0}" == "1" || "${ELMC_FAST:-}" == "true" ]]; then
  echo "==> elmc compile (FAST: reachable-only IR, disk cache, skip wasm-opt/probes)"
else
  echo "==> elmc compile (IR lower + WASM emit; uses .elmc-cache/ir when present)"
fi
echo "    Progress lines are prefixed with [elmc] on stderr."
"$ROOT/scripts/mix-run-limited.sh" elmc -e "
out = \"$OUT\"
if System.get_env(\"ELMC_KEEP_OUT\") not in [\"1\", \"true\"] do
  File.rm_rf!(out)
end
fast? = System.get_env(\"ELMC_FAST\") in [\"1\", \"true\"]
case Elmc.compile(\"$APP\", %{
  out_dir: out,
  targets: [:wasm],
  web: true,
  entry_module: \"Main\",
  strip_dead_code: true,
  wasm_strict: true,
  fast: fast?
}) do
  {:ok, _} ->
    IO.puts(\"WASM web build OK: #{out}\")
    IO.puts(\"  host: #{Path.join(out, \"host/browser.html\")}\")
    IO.puts(\"  wasm: #{Path.join(out, \"wasm/elmc_generated.wat\")}\")

  {:error, reason} ->
    IO.inspect(reason, label: \"compile failed\")
    System.halt(1)
end
"

WAT="$OUT/wasm/elmc_generated.wat"
WASM="$OUT/wasm/app.wasm"

if ! command -v wat2wasm >/dev/null 2>&1; then
  echo "error: wat2wasm not found (install wabt)" >&2
  exit 1
fi

wat2wasm "$WAT" -o "$WASM"
bytes="$(wc -c < "$WASM" | tr -d ' ')"
echo "Linked: $WASM (${bytes} bytes)"

if [[ "$SKIP_WASM_OPT" != "1" ]]; then
  OPT_BIN="$(ensure_wasm_opt)"
  # -Oz shrinks raw; --converge squeezes a bit more. Multivalue is required for
  # elmc RC (result i32 i32) exports/calls.
  WASM_OPT_LEVEL="${WASM_OPT_LEVEL:--Oz}"
  "$OPT_BIN" "$WASM_OPT_LEVEL" --converge --enable-multivalue "$WASM" -o "$WASM"
  bytes="$(wc -c < "$WASM" | tr -d ' ')"
  echo "Optimized: $WASM (${bytes} bytes) via $OPT_BIN $WASM_OPT_LEVEL --converge"
else
  echo "==> SKIP_WASM_OPT=1 (raw wat2wasm output kept)"
fi

if [[ "$KEEP_WAT" != "1" ]]; then
  rm -f "$WAT"
  echo "Removed WAT (set KEEP_WAT=1 to keep)"
fi

echo "==> wasm compile gate (stubs/skips/constructor_tags)"
ELMC_OUT_DIR="$OUT" "$ROOT/scripts/mix-run-limited.sh" elmc test/support/validate_elm_pebble_dev_wasm.exs

if [[ "$SKIP_VERIFY" != "1" && -f "$APP/dist/index.html" ]]; then
  echo "==> wasm page-data probe (Node)"
  node "$ROOT/elmc/test/support/wasm_browser_page_data_probe_runner.mjs" "$OUT"
  if [[ -f "$APP/dist/all-paths.json" ]]; then
    echo "==> wasm route content.dat probe (all-paths)"
    node "$ROOT/elmc/test/support/wasm_route_bytes_content_dat_probe_runner.mjs" "$APP/dist"
  fi
fi

# Precompress large transfer targets before optional host minify refreshes .br.
python3 - <<PY
from pathlib import Path
import json

try:
    import brotli
except ImportError as exc:  # pragma: no cover
    raise SystemExit("python brotli package required for precompress") from exc

out = Path("$OUT")
manifest = out / "wasm" / "elmc_wasm.manifest.json"
data = json.loads(manifest.read_text())
print(
    "Manifest:",
    manifest.stat().st_size,
    "bytes;",
    "minified=",
    data.get("minified"),
    "closure_count=",
    data.get("closure_count") or len(data.get("closures") or []),
    "immortal_strings=",
    (
        len(data["immortal_strings"])
        if isinstance(data.get("immortal_strings"), (list, dict))
        else 0
    ),
)

precompress = [
    out / "wasm" / "app.wasm",
    manifest,
]
precompress += sorted((out / "host").glob("*.js"))
for path in precompress:
    if not path.is_file():
        continue
    raw = path.read_bytes()
    br_path = path.with_name(path.name + ".br")
    br_path.write_bytes(brotli.compress(raw, quality=11))
    print(f"Brotli: {br_path.name} ({br_path.stat().st_size} bytes, from {len(raw)})")
PY

# Minify host JS in dist (sources under elmc-wasm-runtime stay readable).
bash "$ROOT/scripts/minify-wasm-host.sh" "$OUT"

# Debug manifesto is for local tooling; omit from transfer directory unless kept.
if [[ "${KEEP_WASM_DEBUG_MANIFEST:-0}" != "1" ]]; then
  rm -f "$OUT/wasm/elmc_wasm.manifest.debug.json"
fi
