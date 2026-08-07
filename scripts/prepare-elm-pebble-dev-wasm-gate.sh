#!/usr/bin/env bash
# Prepare elm_pebble_dev so elmc can compile Main → WASM on cold CI.
#
# - npm install (elm-pages, elm-tailwind-classes, …)
# - seed ELM_HOME packages from elm_pebble_dev/elm.json (+ transitive)
# - generate .elm-tailwind and .elm-pages (gitignored)
#
# Usage:
#   ./scripts/prepare-elm-pebble-dev-wasm-gate.sh
#   ELM_HOME=/path/to/elm-home ./scripts/prepare-elm-pebble-dev-wasm-gate.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/elm_pebble_dev"
ELM_HOME="${ELM_HOME:-${HOME}/.elm}"
export ELM_HOME

if [[ ! -d "$APP" ]]; then
  echo "error: missing $APP" >&2
  exit 1
fi

echo "==> npm ci (elm_pebble_dev)"
if [[ -f "$APP/package-lock.json" ]]; then
  (cd "$APP" && npm ci --no-audit --no-fund)
else
  (cd "$APP" && npm install --no-audit --no-fund)
fi

# Seed exact direct + indirect deps from elm.json into ELM_HOME *before* elm-pages gen.
# CI uses a sparse seeded home that does not include dillonkearns/elm-pages (and friends).
echo "==> seed Elm packages for elm_pebble_dev into ${ELM_HOME}"
SEED_FROM_ELM_JSON="$APP/elm.json" "$ROOT/scripts/seed-elm-packages.sh"

echo "==> gen:tailwind"
(cd "$APP" && npm run gen:tailwind)

echo "==> elm-pages gen"
# Drop stale generated routes/fetchers (deleted app routes leave orphans under
# elm-stuff/elm-pages that elmc still loads via elm.json source-directories).
rm -rf "$APP/.elm-pages" \
  "$APP/elm-stuff/elm-pages/.elm-pages" \
  "$APP/elm-stuff/elm-pages/client/.elm-pages" \
  "$APP/elm-stuff/elm-pages/server/.elm-pages" \
  "$APP/elm-stuff/elm-pages/client/app" \
  "$APP/elm-stuff/elm-pages/server/app"
(cd "$APP" && npx elm-pages gen)

if [[ ! -f "$APP/.elm-pages/Main.elm" ]]; then
  echo "error: elm-pages gen did not create .elm-pages/Main.elm" >&2
  exit 1
fi

if [[ ! -f "$APP/.elm-tailwind/Tailwind.elm" ]]; then
  echo "error: gen:tailwind did not create .elm-tailwind/Tailwind.elm" >&2
  exit 1
fi

echo "elm_pebble_dev wasm gate prep OK"
