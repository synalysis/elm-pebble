#!/usr/bin/env bash
# Build elm_pebble_dev (elm-pages + WASM) and serve dist/ for browser smoke.
#
# Usage:
#   ./scripts/serve-elm-pebble-dev-wasm.sh [port]
#
# Environment:
#   PORT              — listen port (default: 8080; overridden by first arg)
#   SKIP_BUILD=1      — skip npm build + wasm compile (serve existing dist/)
#   SKIP_VERIFY=1     — skip Node page-data probe after wasm build
#
# Open after start:
#   http://localhost:<port>/wasm-web/host/browser.html

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/elm_pebble_dev"
PORT="${1:-${PORT:-8080}}"
SKIP_BUILD="${SKIP_BUILD:-0}"
SKIP_VERIFY="${SKIP_VERIFY:-0}"

cd "$APP"

if [[ "$SKIP_BUILD" != "1" ]]; then
  echo "==> elm-pages build"
  npm run build

  echo "==> WASM web build (includes page-data probe when dist/index.html exists)"
  echo "    IR lower often takes 20–40 min; watch for [elmc] progress on stderr."
  SKIP_VERIFY="${SKIP_VERIFY:-0}" npm run build:wasm

  if [[ "$SKIP_VERIFY" == "1" ]]; then
    echo "==> SKIP_VERIFY=1 (page-data probe skipped during build)"
  fi
else
  echo "==> SKIP_BUILD=1 (serving existing dist/)"
fi

if [[ ! -f dist/index.html ]]; then
  echo "error: dist/index.html missing (run without SKIP_BUILD=1)" >&2
  exit 1
fi

if [[ ! -f dist/wasm-web/host/browser.html ]]; then
  echo "error: dist/wasm-web/host/browser.html missing (run wasm build)" >&2
  exit 1
fi

# Keep served host JS in sync with elmc-wasm-runtime (avoids stale rc_runtime after host-only edits).
echo "==> sync WASM host runtime from elmc-wasm-runtime"
HOST_SRC="$ROOT/elmc-wasm-runtime/host"
HOST_DST="$APP/dist/wasm-web/host"
mkdir -p "$HOST_DST"
shopt -s nullglob
for host_file in "$HOST_SRC"/*.js; do
  cp "$host_file" "$HOST_DST/$(basename "$host_file")"
done
cp "$HOST_SRC/browser.html" "$HOST_DST/browser.html"

echo "==> minify/bundle synced host JS for transfer"
bash "$ROOT/scripts/minify-wasm-host.sh" "$APP/dist/wasm-web"

if [[ ! -f dist/wasm-web/host/boot.js ]]; then
  echo "error: dist/wasm-web/host/boot.js missing after minify" >&2
  exit 1
fi

if [[ "${KEEP_WASM_DEBUG_MANIFEST:-0}" != "1" ]]; then
  rm -f dist/wasm-web/wasm/elmc_wasm.manifest.debug.json
fi

URL="http://localhost:${PORT}/wasm-web/host/browser.html"
echo ""
echo "Serving $APP/dist on port ${PORT} (Brotli negotiation for .br sidecars)"
echo "  WASM browser: ${URL}"
echo "  elm-pages:    http://localhost:${PORT}/"
echo ""
echo "Press Ctrl+C to stop."
echo ""

exec python3 "$ROOT/scripts/serve-static-brotli.py" dist --port "$PORT" --bind 0.0.0.0
