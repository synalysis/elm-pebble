#!/usr/bin/env bash
# Run mix test with a virtual memory cap so a runaway suite does not OOM the host.
# Override via TEST_ULIMIT_V_KB, ELIXIR_ERL_OPTIONS.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG="${1:-ide}"
shift || true

ULIMIT_V_KB="${TEST_ULIMIT_V_KB:-6291456}"   # 6 GiB virtual (override for heavy suites)

export ELIXIR_ERL_OPTIONS="${ELIXIR_ERL_OPTIONS:-+S 1:1 +MMscs 256}"

# Soft-only: keep BEAM capped, but allow node wasm probes (run_without_ulimit)
# to raise their soft limit up to the process hard limit for WebAssembly.Memory.
ulimit -S -v "${ULIMIT_V_KB}"

cd "${ROOT}/${PKG}"
exec mix test --max-cases 1 "$@"
