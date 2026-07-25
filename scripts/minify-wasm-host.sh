#!/usr/bin/env bash
# Bundle + minify elmc WASM host JS for browser transfer, then refresh .br.
#
# Default: esbuild-bundle boot.js (and its ESM imports) into a single boot.js,
# then delete the other host modules from dist/. Sources under
# elmc-wasm-runtime/host remain untouched for Node probes.
#
# Usage:
#   ./scripts/minify-wasm-host.sh <wasm-web-out-dir>
#
# Environment:
#   SKIP_MINIFY_HOST=1     — no-op
#   HOST_BUNDLE=0          — minify each module in place (legacy multi-file)
#   KEEP_HOST_MODULES=1    — after bundle, keep imported modules (debug)
#   ESBUILD                — path to esbuild binary (optional)
#   SKIP_BROTLI=1          — skip regenerating .br after minify

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-}"
if [[ -z "$OUT" ]]; then
  echo "usage: $0 <wasm-web-out-dir>" >&2
  exit 2
fi
if [[ "$OUT" != /* ]]; then
  OUT="$ROOT/$OUT"
fi

HOST="$OUT/host"
if [[ ! -d "$HOST" ]]; then
  echo "error: missing host dir: $HOST" >&2
  exit 1
fi

if [[ "${SKIP_MINIFY_HOST:-0}" == "1" ]]; then
  echo "SKIP_MINIFY_HOST=1 — leaving host JS unminified"
  exit 0
fi

# Always refresh dist host from elmc-wasm-runtime before bundling. Minify used to
# re-bundle an already-minified boot.js (siblings deleted), so host-only fixes
# never reached the browser until a full serve/build sync.
HOST_SRC="${ELMC_WASM_HOST_SRC:-$ROOT/elmc-wasm-runtime/host}"
if [[ "${SKIP_SYNC_HOST:-0}" != "1" && -d "$HOST_SRC" ]]; then
  echo "==> sync host JS from $HOST_SRC"
  shopt -s nullglob
  for host_file in "$HOST_SRC"/*.js; do
    cp "$host_file" "$HOST/$(basename "$host_file")"
  done
  if [[ -f "$HOST_SRC/browser.html" ]]; then
    cp "$HOST_SRC/browser.html" "$HOST/browser.html"
  fi
  shopt -u nullglob
fi

find_esbuild() {
  if [[ -n "${ESBUILD:-}" && -x "${ESBUILD}" ]]; then
    echo "$ESBUILD"
    return 0
  fi
  if command -v esbuild >/dev/null 2>&1; then
    command -v esbuild
    return 0
  fi
  local cand
  for cand in \
    "$ROOT/elm_pebble_dev/node_modules/.bin/esbuild" \
    "$ROOT/node_modules/.bin/esbuild"; do
    if [[ -x "$cand" ]]; then
      echo "$cand"
      return 0
    fi
  done
  return 1
}

ESBUILD_BIN="$(find_esbuild)" || {
  echo "error: esbuild not found (npm i in elm_pebble_dev, or set ESBUILD=)" >&2
  exit 1
}

shopt -s nullglob
files=("$HOST"/*.js)
if [[ ${#files[@]} -eq 0 ]]; then
  echo "error: no host JS under $HOST" >&2
  exit 1
fi

before=0
for f in "${files[@]}"; do
  before=$((before + $(wc -c < "$f" | tr -d ' ')))
done

HOST_BUNDLE="${HOST_BUNDLE:-1}"

if [[ "$HOST_BUNDLE" == "1" && -f "$HOST/boot.js" ]]; then
  echo "==> bundle+minify WASM host via $ESBUILD_BIN"
  tmp="$HOST/boot.bundle.tmp.js"
  "$ESBUILD_BIN" "$HOST/boot.js" \
    --bundle \
    --minify \
    --legal-comments=none \
    --format=esm \
    --outfile="$tmp"
  mv "$tmp" "$HOST/boot.js"
  after="$(wc -c < "$HOST/boot.js" | tr -d ' ')"
  echo "  boot.js (bundled): ${before} -> ${after}"

  if [[ "${KEEP_HOST_MODULES:-0}" != "1" ]]; then
    for f in "$HOST"/*.js; do
      base="$(basename "$f")"
      if [[ "$base" != "boot.js" ]]; then
        rm -f "$f" "$f.br"
      fi
    done
    echo "  removed non-boot host modules (KEEP_HOST_MODULES=1 to keep)"
  fi
else
  echo "==> minify WASM host JS modules via $ESBUILD_BIN"
  after=0
  for f in "${files[@]}"; do
    b="$(wc -c < "$f" | tr -d ' ')"
    "$ESBUILD_BIN" "$f" --minify --legal-comments=none --allow-overwrite --outfile="$f" >/dev/null
    a="$(wc -c < "$f" | tr -d ' ')"
    after=$((after + a))
    echo "  $(basename "$f"): ${b} -> ${a}"
  done
  echo "Host JS total: ${before} -> ${after} bytes"
fi

if [[ "${SKIP_BROTLI:-0}" == "1" ]]; then
  exit 0
fi

python3 - <<PY
from pathlib import Path
try:
    import brotli
except ImportError as exc:
    raise SystemExit("python brotli package required to refresh .br") from exc

host = Path("$HOST")
# Drop stale .br for removed modules.
for br in host.glob("*.js.br"):
    js = br.with_name(br.name[: -len(".br")])
    if not js.is_file():
        br.unlink()

for path in sorted(host.glob("*.js")):
    raw = path.read_bytes()
    br_path = path.with_name(path.name + ".br")
    br_path.write_bytes(brotli.compress(raw, quality=11))
    print(f"  Brotli: {br_path.name} ({br_path.stat().st_size} bytes)")
PY
