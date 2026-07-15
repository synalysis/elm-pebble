# elm_pebble_dev WASM build (Phase 4 north-star)

Build from the repo root or from `elm_pebble_dev/`:

```bash
# from elm_pebble_dev/
npm run build:wasm
npm run verify:wasm   # requires dist/index.html from `npm run build`

# build site + wasm + verify + serve (from repo root or via npm)
./scripts/serve-elm-pebble-dev-wasm.sh [port]
# or: cd elm_pebble_dev && npm run serve:wasm
```

Equivalent compile (repo root):

```bash
./scripts/build-elm-pebble-dev-wasm.sh [out-dir]
elmc compile elm_pebble_dev --out-dir dist/wasm-web --target wasm --web
```

Default output directory: `elm_pebble_dev/dist/wasm-web`.

For the full site app, use non-strict WASM validation (same as the build script): skipped
platform helpers are expected until the web kernel surface is complete.

```bash
# via mix (see scripts/build-elm-pebble-dev-wasm.sh)
Elmc.compile("elm_pebble_dev", targets: [:wasm], web: true, wasm_strict: false, ...)
```

Outputs (under `dist/wasm-web/` by default):

- `wasm/elmc_generated.wat`
- `wasm/elmc_wasm.manifest.json`
- `wasm/app.wasm` (when `wat2wasm` is available)
- `host/loader.js` + `host/rc_runtime.js` + `host/json_runtime.js` + `host/bytes_runtime.js` (copied from `elmc-wasm-runtime/host/`)
- `host/browser.html`
- `runtime/elmc_runtime.c` (pruned from manifest imports)

BackendTask route data is evaluated at compile time in Elixir; the browser
loads only the WASM client bundle plus the thin JS host.

## Boot status

`elmc_fn_Main_main` compiles and boots in Node (`wasm_web_smoke_test.exs`):

- Plan lowering: **0 skips** (with `wasm_strict: false` for the full site app)
- Browser program init/view closures run (`stage=ok`)
- Init model is valid (`pageData = Err ""` for elm-pages before host data arrives)
- After `pageDataFromJs` delivers bytes from `elm_pebble_dev/dist/index.html`, the index route
  renders with title **Elm Pebble | Watch faces & apps in Elm** (see `wasm_web_page_data_test.exs`)
- Incoming/outgoing Elm ports lower to `runtime.port_incoming_sub` / `runtime.port_outgoing`
  (see `wasm_port_incoming_test.exs`); boot can deliver `opts.incomingPorts` and re-run update/view
- `Sub.map` / `Sub.batch` and `Cmd.map` / `Cmd.batch` build platform manager records in WASM;
  the JS host walks that tree after subscriptions run to register incoming port handlers with
  composed taggers (identity port callbacks plus outer `Sub.map` functions)
- `Elm.Kernel.Bytes` lowers to `runtime.bytes_cmd` for decode/encode/width/read primitives
  (see `wasm_web_bytes_test.exs`); host can build bytes via `helpers.bytesFromList([...])`

Main boot probe:

```bash
wat2wasm dist/wasm/elmc_generated.wat -o dist/wasm/app.wasm
node elmc/test/support/wasm_browser_probe_runner.mjs dist elmc_fn_Main_main
```

Page-data gate (index route title after host bytes):

```bash
./scripts/build-elm-pebble-dev-wasm.sh elm_pebble_dev/dist/wasm-web
node elmc/test/support/wasm_browser_page_data_probe_runner.mjs elm_pebble_dev/dist/wasm-web
```

ExUnit (compile + link + page-data probe, tagged `:slow`):

```bash
./scripts/mix-test-limited.sh elmc test/wasm_web_page_data_test.exs --include slow
./scripts/mix-test-limited.sh elmc test/wasm_web_boot_test.exs --include slow
```

Local inspect script (build + manifest/runtime summary, from repo root):

```bash
./scripts/mix-run-limited.sh elmc test/support/check_elm_pebble_dev_wasm.exs
cd elmc && node test/support/wasm_browser_page_data_probe_runner.mjs tmp/elm_pebble_dev_wasm
```

Browser smoke (serve `elm_pebble_dev/dist` so `wasm-web/host/../../index.html` resolves):

```bash
cd elm_pebble_dev
npm run build && npm run build:wasm
npx --yes serve dist -p 4173
# open http://localhost:4173/wasm-web/host/browser.html
# optional override: ?pageHtml=/index.html
```

Runtime pruning probe (rc_track list fixture; paths relative to `elmc/`):

```bash
./scripts/mix-run-limited.sh elmc test/support/check_runtime_prune.exs
```

## Browser smoke (elm-pages route bytes)

```bash
cd elm_pebble_dev
npm run build        # elm-pages → dist/index.html
npm run build:wasm   # → dist/wasm-web/
npm run verify:wasm   # Node page-data gate
npm run serve:wasm   # http://localhost:8080/wasm-web/host/browser.html

Or one command from repo root (build + verify + serve):

```bash
./scripts/serve-elm-pebble-dev-wasm.sh [port]
```

Override the HTML source with `?pageHtml=/path/relative/to/dist/index.html`.
