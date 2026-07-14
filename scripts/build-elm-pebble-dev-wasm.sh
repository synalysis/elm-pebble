#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/elm_pebble_dev"
OUT="${1:-$APP/dist/wasm-web}"

cd "$ROOT/elmc"
mix run -e "
out = Path.expand(\"$OUT\")
File.rm_rf!(out)
case Elmc.compile(Path.expand(\"../elm_pebble_dev\", __DIR__), %{
  out_dir: out,
  targets: [:wasm],
  web: true,
  entry_module: \"Main\",
  strip_dead_code: true,
  wasm_strict: false
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

if command -v wat2wasm >/dev/null 2>&1; then
  wat2wasm "$OUT/wasm/elmc_generated.wat" -o "$OUT/wasm/app.wasm"
  echo "Linked: $OUT/wasm/app.wasm"
fi
