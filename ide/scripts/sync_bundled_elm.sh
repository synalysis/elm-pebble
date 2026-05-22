#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
DEST="${ROOT}/ide/priv/bundled_elm"

mkdir -p "$DEST"

sync_dir() {
  local source="$1"
  local target="$2"

  rm -rf "$DEST/$target"
  cp -a "$source" "$DEST/$target"
}

sync_dir "$ROOT/shared/elm" "shared-elm"
sync_dir "$ROOT/packages/elm-pebble/elm-watch/src" "pebble-watch-src"
sync_dir "$ROOT/packages/elm-pebble-companion-core/src" "pebble-companion-core-src"
sync_dir "$ROOT/packages/elm-pebble-companion-preferences/src" "pebble-companion-preferences-src"

echo "Synced bundled Elm sources to $DEST"
