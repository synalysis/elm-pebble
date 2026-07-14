# elm_pebble_dev WASM build (Phase 4 north-star)

Build from the repo root or from `elm_pebble_dev/`:

```bash
# from elm_pebble_dev/
npm run build:wasm

# or explicitly
./scripts/build-elm-pebble-dev-wasm.sh [out-dir]
```

Equivalent compile:

```bash
elmc compile elm_pebble_dev --out-dir dist --target wasm --web
```

Outputs:

- `dist/wasm/elmc_generated.wat`
- `dist/wasm/elmc_wasm.manifest.json`
- `dist/host/loader.js` + `dist/host/rc_runtime.js` (copied from `elmc-wasm-runtime/host/`)
- `dist/host/browser.html` (when `wat2wasm` links `dist/wasm/app.wasm`)

BackendTask route data is evaluated at compile time in Elixir; the browser
loads only the WASM client bundle plus the thin JS host.

## Boot status

`elmc_fn_Main_main` compiles and boots in Node (`wasm_web_smoke_test.exs`):

- Plan lowering: **0 skips**
- Browser program init/view closures run (`stage=ok`)
- Init model is valid (`pageData = Err ""` for elm-pages before host data arrives)
- View renders the platform shell; title shows **Page Data Error** until `pageDataFromJs` delivers bytes
- Incoming/outgoing Elm ports lower to `runtime.port_incoming_sub` / `runtime.port_outgoing`
  (see `wasm_port_incoming_test.exs`); boot can deliver `opts.incomingPorts` and re-run update/view
- `Sub.map` / `Sub.batch` and `Cmd.map` / `Cmd.batch` build platform manager records in WASM;
  the JS host walks that tree after subscriptions run to register incoming port handlers with
  composed taggers (identity port callbacks plus outer `Sub.map` functions)
- `Elm.Kernel.Bytes` lowers to `runtime.bytes_cmd` for decode/encode/width/read primitives
  (see `wasm_web_bytes_test.exs`); host can build bytes via `helpers.bytesFromList([...])`

Probe:

```bash
wat2wasm dist/wasm/elmc_generated.wat -o dist/wasm/app.wasm
node elmc/test/support/wasm_browser_probe_runner.mjs dist elmc_fn_Main_main
```
