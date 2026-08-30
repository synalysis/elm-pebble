#!/usr/bin/env bash
# Fast compile loops for a *small* Elm app (not full elm_pebble_dev).
#
# Usage:
#   ./scripts/elmc-fast-compile.sh path/to/project [out_dir]
#
# Environment:
#   ELMC_FAST=1          — default; skip wasm-opt style post steps when used with wasm build
#   ELMC_IR_PARALLEL=N   — parallel module lower (default 2)
#   ELMC_KEEP_OUT=1      — do not wipe out_dir before compile
#   TARGETS=wasm|c       — default wasm
#
# Prefer this over elm_pebble_dev for host/WebGL iteration: minutes vs tens of minutes.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:?usage: elmc-fast-compile.sh <project_dir> [out_dir]}"
OUT="${2:-$APP/.elmc-build}"
if [[ "$APP" != /* ]]; then APP="$ROOT/$APP"; fi
if [[ "$OUT" != /* ]]; then OUT="$ROOT/$OUT"; fi

export ELMC_FAST="${ELMC_FAST:-1}"
export ELMC_IR_PARALLEL="${ELMC_IR_PARALLEL:-2}"
export TEST_ULIMIT_V_KB="${TEST_ULIMIT_V_KB:-10485760}"
export ELIXIR_ERL_OPTIONS="${ELIXIR_ERL_OPTIONS:-+S ${ELMC_IR_PARALLEL}:${ELMC_IR_PARALLEL} +MMscs 512}"

TARGETS="${TARGETS:-wasm}"

echo "==> fast elmc compile ($APP -> $OUT, targets=$TARGETS)"
"$ROOT/scripts/mix-run-limited.sh" elmc -e "
out = \"$OUT\"
if System.get_env(\"ELMC_KEEP_OUT\") not in [\"1\", \"true\"] do
  File.rm_rf!(out)
end
targets =
  case \"$TARGETS\" do
    \"c\" -> [:c]
    _ -> [:wasm]
  end
opts = %{
  out_dir: out,
  targets: targets,
  web: targets == [:wasm],
  entry_module: \"Main\",
  strip_dead_code: true,
  wasm_strict: true,
  fast: true,
  ir_progress: true
}
case Elmc.compile(\"$APP\", opts) do
  {:ok, result} ->
    n = length(result.ir.modules)
    IO.puts(\"OK: #{n} IR modules -> #{out}\")
  {:error, reason} ->
    IO.inspect(reason, label: \"compile failed\")
    System.halt(1)
end
"
