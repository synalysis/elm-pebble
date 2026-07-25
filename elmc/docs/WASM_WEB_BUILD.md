# Generic Elm → WASM Web Parity

Build from the repo root or from `elm_pebble_dev/`:

```bash
# from elm_pebble_dev/
npm run build:wasm
npm run verify:wasm   # Node page-data gate (also runs at end of build:wasm)
npm run verify:wasm:hero   # /wasm HeroScene WebGL entities + draws (needs dist build)
npm run verify:wasm:browser   # Playwright browser.html smoke (needs chromium)

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

**Pure web apps** (`Browser.*` / `Platform.worker`, official `elm/*` only) should compile with
`wasm_strict: true` (the default). Pebble draw/cmd/sub specials are excluded from the web
special-value dispatcher; reaching `pebble_cmd` / `render_cmd` / `pebble_sub` under `web: true`
records an unsupported lowering.

The elm-pages site (`elm_pebble_dev`) still uses `wasm_strict: false` in its build script
because Pebble-only plan ops remain in that combined graph. Stubs/skips for browser-relevant
paths are gated empty via `check_elm_pebble_dev_wasm.exs`.

```bash
# via mix (see scripts/build-elm-pebble-dev-wasm.sh)
Elmc.compile("elm_pebble_dev", targets: [:wasm], web: true, wasm_strict: false, ...)
```

## Supported surface matrix (`wasm_strict: true`)

| Package / area | Status | Gate |
|----------------|--------|------|
| `Browser.sandbox` / `element` / `document` / `application` | compile + boot | `wasm_web_strict_sandbox_test.exs` |
| `Platform.worker` | lowers to `browser_cmd` kind 8 | plan lower |
| `Html` / `VirtualDom` / `Svg` | `html_cmd` text/node/map/event/NS | `wasm_web_{events,svg}_test.exs` |
| `WebGL` / `elm-3d-scene` (HeroScene) | host `webgl_*` + MJS bridges; canvas draws; Scene3d mesh helpers plan-lower | `wasm_web_hero_scene_test.exs` / `verify:wasm:hero` |
| `Html.Keyed` / `Html.Lazy` lazy2–4 | `html_cmd` kinds 9–13 + `vdom_patch.js` | `wasm_web_keyed_nav_test.exs` |
| `Browser.Events` mouse/key (Decoder msg) | `dom_sub` kinds 5–8/10 + Json decode on raw event | host `installDomSub` |
| `VirtualDom.on` / `Html.Events.on*` | `html_cmd` kind 8 | `wasm_web_events_test.exs` |
| `Browser.Dom.focus` / `setTitle` / `getViewport` | `browser_cmd` + `browser_get_viewport` task | effects lowering |
| `Html.map` events | mapper composed at dispatch + real decoder args | `wasm_web_map_events_test.exs` |
| elm-pages multi-route bytes | `pageDataFromJs` on boot + nav | `wasm_web_multi_route_bytes_test.exs` (`:wasm_elm_pages_corpus`) |
| `Sub.none` / `Sub.batch` / `Sub.map` | `dom_sub` + platform managers | boot |
| `Task` / `Process.sleep` / `Scheduler` | `task_*` / `process_*` | `wasm_web_task_test.exs` |
| `Time.now` / `Time.every` / `Time.here` / `Time.zoneOffsetMinutes` | host time imports | `wasm_web_time_every_test.exs` |
| `Http` | `http_*` host (headers, bytes, timeout, Result errors) | `wasm_web_http_behavior_test.exs` |
| `File.Download` / `File.Select` | `file_*` host | `wasm_web_file_test.exs` |
| `Bytes` / `Json` / `Parser` | `bytes_cmd` / `json_cmd` / `parser_cmd` | `wasm_web_bytes_test.exs` |
| `Random.generate` | `random_generate` web cmd | web_kernel |
| `Regex` (`Elm.Kernel.Regex`) | `regex_*` host | web_kernel |
| `Dict` / `Set` / `==` | structural equality in host | `valuesEqual` / `compareValues` |
| Pebble UI/Cmd/Events | **not in web graph** | dispatcher filter + plan guards |

CI smoke:

```bash
export TEST_ULIMIT_V_KB=6291456 ELIXIR_ERL_OPTIONS="+S 1:1 +MMscs 256"
./scripts/mix-test-limited.sh elmc test/wasm_web_*_test.exs
./scripts/mix-run-limited.sh elmc test/support/check_elm_pebble_dev_wasm.exs
```

Small web fixtures compile with `wasm_strict: true` by default.

Outputs (under `dist/wasm-web/` by default):

- `wasm/app.wasm` (+ `app.wasm.br`; WAT removed unless `KEEP_WAT=1`)
- `wasm/elmc_wasm.manifest.json` (slim when `web: true`; debug sidecar alongside)
- `host/boot.js` (bundled+minified from `elmc-wasm-runtime/host/`; one transfer)
- `host/browser.html`
- `runtime/elmc_runtime.c` (pruned from manifesto imports)

Size / boot report:

```bash
npm run bench:wasm
# optional gate: BUDGET_BR_KB=160 npm run bench:wasm
npm run bench:wasm:browser   # Playwright first-load JS vs WASM (needs playwright)
# NETWORK=off|fast3g|slow3g|all  CACHE=cold|warm|both  RUNS=3
```

`scripts/serve-static-brotli.py` defaults to `Cache-Control: no-cache` so local
`serve-elm-pebble-dev-wasm.sh` rebuilds of stable-URL artifacts (`boot.js`,
`app.wasm`, manifesto) show up without a hard refresh. Browser warm-cache benches
pass `--immutable-cache` for long-lived asset caching (`Vary: Accept-Encoding` on
Brotli still applies whenever `.br` sidecars are negotiated).
The WASM host shell (`browser.html`) starts with an empty `<title>`; the Document
title from Elm fills in after boot so readiness waits are not fooled by a static
placeholder.

Browser boot overlaps manifesto + WASM fetch, uses `WebAssembly.compileStreaming`
when the response MIME is `application/wasm`, and records phase timings on
`globalThis.__elmcBootTiming` (surfaced in `bench:wasm:browser` as `wasm_boot`).
First paint also shares one `index.html` fetch for elm-pages styles + `pageData`
bytes, skips the post-port `valueReaches` walk in the browser, and skips the
full VDOM `innerText` scrape (DOM readiness is enough).

RC epilogues currently use `runtime.release_unless_reachable_from_roots` (fn_out
+ params as roots). Ownership fixes in flight (`tuple2` / `list_cons` /
`make_closure` named-local consume, `Html.map` mapper retain, publish/CFG
transfer) still leave some owned aliases under `$fn_out`; plain LIFO
`runtime.release` corrupts page-data boot until those are gone.
`new_immortal_string` interns handles by literal id so repeated literals share
one immortal string handle (marked `immortal`, skipped by RC walks).

View trees share VDOM nodes via retain instead of deep-cloning on every
`Html.map` / node adopt (map is a lightweight wrapper resolved at mount).
Host also retains on `record_get` / tuple builders / `make_closure` captures /
list builders (`list_cons` / `list_append`) / Sub·Cmd platform managers so
graphs stay RC-correct.

Transfer-size work (minify exports, dense immortal strings, bundled host, wasm-opt -Oz
--converge, Brotli) has reached diminishing returns for this app: the manifesto is mostly
real content/Tailwind strings, and packing/sidecars did not beat Brotli on the JSON table.

BackendTask route data is evaluated at compile time in Elixir; the browser
loads only the WASM client bundle plus the thin JS host.

**Route bytes (static):** build emits per-route base64 in a manifest
(`route_bytes_manifest` in `elmc_wasm.manifest.json`) or embeds bytes in each
route’s `index.html` (`__ELM_PAGES_BYTES_DATA__`). The host registers bytes on
boot and re-delivers `pageDataFromJs` on `onUrlChange`.

**Route bytes (runtime fetch):** when a path is missing from the static manifest,
`route_bytes.js` prefers fetching `/<path>/content.dat` (elm-pages SPA contract —
same buffer `pageDataFromJs` expects), then falls back to scraping
`/<path>/index.html` embedded `__ELM_PAGES_BYTES_DATA__`.

Serve the full elm-pages `dist/` with the WASM SPA shell so client navigation and
refresh stay on the host:

```bash
./scripts/serve-elm-pebble-dev-wasm.sh 8080
# → http://localhost:8080/  (SPA shell = wasm-web/host/browser.html)
```

## Boot status

`elmc_fn_Main_main` compiles and boots in Node (`wasm_web_smoke_test.exs`):

- Plan lowering: **`stub_functions == []`** and **no browser-relevant skips** in the debug manifest (`KEEP_WASM_DEBUG_MANIFEST=1` during `verify:wasm` / `build-elm-pebble-dev-wasm.sh`)
- Browser program init/view closures run (`stage=ok`)
- Init model is valid (`pageData = Err ""` for elm-pages before host data arrives)
- After `pageDataFromJs` delivers bytes from `elm_pebble_dev/dist/index.html`, the index route
  renders with title **Elm Pebble | Watch faces & apps in Elm** (see `wasm_web_page_data_test.exs`)
- Incoming/outgoing Elm ports lower to `runtime.port_incoming_sub` / `runtime.port_outgoing`
  (see `wasm_port_incoming_test.exs`); boot can deliver `opts.incomingPorts` and re-run update/view
- `Sub.map` / `Sub.batch` and `Cmd.map` / `Cmd.batch` build platform manager records in WASM;
  the JS host walks that tree after subscriptions run to register incoming port handlers with
  composed taggers (identity port callbacks plus outer `Sub.map` functions)
- `Json.Decode` / `Json.Encode` lower to direct `runtime.json_decode_*` / `runtime.json_encode_*` imports (see `wasm_web_json_test.exs`, `wasm_web_json_decode_error_test.exs`); structured `Json.Decode.Error` values use manifest `constructor_tags`
- `Elm.Kernel.Bytes` lowers to `runtime.bytes_cmd` for decode/encode/width/read primitives
  (see `wasm_web_bytes_test.exs`); host can build bytes via `helpers.bytesFromList([...])`
- `Html.Events` / SVG `nodeNS` lower to `runtime.html_cmd` kinds 7–8 (see `wasm_web_events_test.exs`, `wasm_web_svg_test.exs`)
- `Task.perform` / `Time.now` / `Time.every` lower to `runtime.task_*` / `runtime.dom_sub` (see `wasm_web_task_test.exs`, `wasm_web_time_every_test.exs`)
- `Random.generate` lowers to `runtime.random_generate` (web cmd, not Pebble encoding)
- `Elm.Kernel.Regex.*` lowers to `runtime.regex_*`
- `Browser.Events` / `Browser.Navigation` / `Browser.Dom.focus` lower through `dom_sub` / `browser_cmd`
- Structural `==` / `compare` for records, lists, unions, Dict/Set keys in the JS host
- `Http.get` / `Http.expect` lower to `runtime.http_*` imports; init/update cmds drain via the host boot loop (see `wasm_web_http_test.exs`)
- `BackendTask.Http` client requests (`get`, `getJson`, `getWithOptions`, `post`, `request`, body/expect helpers, `withMetadata`) lower to `runtime.backend_task_http_*` imports and run in the browser via `fetch` (see `wasm_web_backend_task_http_*_test.exs`). Task failures use typed `BackendTask.Http.Error` constructors when present in the manifest `constructor_tags` map (`BadStatus`, `Timeout`, `NetworkError`, `BadBody` with structured `Json.Decode.Error` values when those tags are available). Nested `withMetadata` chains combine inner-to-outer against one response metadata record. Server-only elm-pages cache (`cacheStrategy` / `cachePath`) is ignored at runtime; compile emits warning `browser_http_cache_ignored` when those fields are `Just` in a `getWithOptions` literal.
- `File.Download.string` lowers through `Elm.Kernel.File.download` → `runtime.file_download_task` (see `wasm_web_file_test.exs`)
- Route record field access stays reachable under web DCE (see `wasm_web_route_field_test.exs`)
- `Elm.Kernel.Parser.isSubString` / `isSubChar` lower to `runtime.parser_cmd`; package-private
  module-name collisions (e.g. `Pattern` in `justinmimbs/date` vs elm-pages) keep both modules
  under package-scoped IR names

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
./scripts/mix-test-limited.sh elmc test/wasm_web_browser_playwright_test.exs --include slow --include browser
```

`build-elm-pebble-dev-wasm.sh` runs stub/skip validation after every build and the Node
page-data probe when `elm_pebble_dev/dist/index.html` exists (`SKIP_VERIFY=1` to skip).

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
npm run verify:wasm   # Node page-data gate (also runs at end of build:wasm)
npm run verify:wasm:browser   # Playwright browser.html smoke (needs chromium)
npm run serve:wasm   # http://localhost:8080/wasm-web/host/browser.html

Or one command from repo root (build + verify + serve):

```bash
./scripts/serve-elm-pebble-dev-wasm.sh [port]
```

Override the HTML source with `?pageHtml=/path/relative/to/dist/index.html`.
