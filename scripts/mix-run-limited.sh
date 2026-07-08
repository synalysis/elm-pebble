#!/usr/bin/env bash
# Run mix run under virtual-memory cap (same guard as mix-test-limited.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG="${1:-elmc}"
shift || true

ULIMIT_V_KB="${TEST_ULIMIT_V_KB:-4194304}"

export ELIXIR_ERL_OPTIONS="${ELIXIR_ERL_OPTIONS:-+S 1:1 +MMscs 256}"

ulimit -v "${ULIMIT_V_KB}"

cd "${ROOT}/${PKG}"
exec mix run --no-start "$@"
