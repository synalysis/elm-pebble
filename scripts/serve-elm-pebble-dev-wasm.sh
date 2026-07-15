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

  echo "==> WASM web build"
  npm run build:wasm

  if [[ "$SKIP_VERIFY" != "1" ]]; then
    echo "==> WASM page-data probe"
    npm run verify:wasm
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

for host_file in json_runtime.js bytes_runtime.js rc_runtime.js boot.js loader.js page_bytes.js page_styles.js; do
  if [[ ! -f "dist/wasm-web/host/$host_file" ]]; then
    echo "error: dist/wasm-web/host/$host_file missing — rebuild with npm run build:wasm" >&2
    exit 1
  fi
done

# Keep served host JS in sync with elmc-wasm-runtime (avoids stale rc_runtime after host-only edits).
echo "==> sync WASM host runtime from elmc-wasm-runtime"
HOST_SRC="$ROOT/elmc-wasm-runtime/host"
HOST_DST="$APP/dist/wasm-web/host"
mkdir -p "$HOST_DST"
for host_file in loader.js rc_runtime.js json_runtime.js bytes_runtime.js boot.js page_bytes.js page_styles.js browser.html; do
  cp "$HOST_SRC/$host_file" "$HOST_DST/$host_file"
done

URL="http://localhost:${PORT}/wasm-web/host/browser.html"
echo ""
echo "Serving $APP/dist on port ${PORT}"
echo "  WASM browser: ${URL}"
echo "  elm-pages:    http://localhost:${PORT}/"
echo ""
echo "Press Ctrl+C to stop."
echo ""

exec python -m http.server "$PORT" --directory dist
