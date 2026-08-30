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

The elm-pages site (`elm_pebble_dev`) compiles with `wasm_strict: true`.
Do not re-expand a host-bridge stub allowlist. The allowlist is empty.
`Elm.Kernel.MJS.*` (including partials) rewrite to `runtime.mjs_*` plan builtins
on web. `Elm.Kernel.WebGL.entity` / `toHtml` (including partials) rewrite to
`runtime.webgl_entity` / `runtime.webgl_to_html`. `Float.Extra.interpolateFrom`
(including 0–2 argument partials and first-class refs) rewrites to
`runtime.float_interpolate_from`. Leftover missing-callees for those names are
diagnosed (`missing_callee_stub` / `wasm_strict`).
Scene3d / BoundingBox3d
and `Browser.Events` / `VirtualDom.on` must not be re-allowlisted — those now
lower or are unused. Stubs/skips for browser-relevant paths are gated empty via
`check_elm_pebble_dev_wasm.exs`. Reachable web helpers must emit SSA or native
WASM fusion (`list_indexed_replace`); they must never be skipped as
`fusion_only`.
If a Pebble `pebble_cmd` / `render_cmd` / `pebble_sub` still reaches WASM emit,
the path traps (`unreachable`) and records `unsupported_platform_op` instead of
returning a silent zero.

```bash
# via mix (see scripts/build-elm-pebble-dev-wasm.sh)
Elmc.compile("elm_pebble_dev", targets: [:wasm], web: true, wasm_strict: true, ...)
```

## Supported surface matrix (`wasm_strict: true`)

| Package / area | Status | Gate |
|----------------|--------|------|
| `Browser.sandbox` / `element` / `document` / `application` | compile + boot | `wasm_web_strict_sandbox_test.exs` |
| `Platform.worker` | lowers to `browser_cmd` kind 8 | plan lower |
| `Html` / `VirtualDom` / `Svg` | `html_cmd` text/node/map/event/NS; official `Html.Attributes.class` / `id` / `title` / `href` / `name` / `placeholder` / `type_` / `target` / `rel` / `alt` / `src` / `download` / `action` / `method` / `for` are attributes; `Html.Attributes.classList` is official `class` of enabled names; `Svg.Attributes.xlinkHref` is official `VirtualDom.attributeNS` (`html_cmd` kind 20 + `setAttributeNS`); `Svg.Keyed.node` is official `VirtualDom.keyedNodeNS` (`html_cmd` kind 10) | `wasm_web_{events,svg,html}_test.exs` |
| `WebGL` / `elm-3d-scene` (HeroScene) | plan `webgl_entity` / `webgl_to_html` + `runtime.mjs_*`; canvas draws; Scene3d mesh helpers plan-lower | `wasm_web_hero_scene_test.exs` / `verify:wasm:hero` |
| `Html.Keyed` / `Html.Lazy` lazy–lazy8 | `html_cmd` kinds 6, 11–13, 16–19 + official thunk `===` (boxed Int/Float/String/Char by value; records/lists by handle); thunk is not called when refs match | `wasm_web_keyed_nav_test.exs` / `wasm_web_lazy_test.exs` |
| `String.fromInt` (native-int) | `runtime.string_from_int` takes the already-unboxed i32 (`elmc_string_from_native_int`). Do not treat that i32 as a handle — `1` is immortal UNIT. `a && (fromInt n == "…")` must keep the real `:string` compare — truthy-phi must not reconstruct it as `as_int` | `wasm_web_string_test.exs` |
| `String.pad` / `indexes` / `indices` / `slice` / `left` / `right` / `dropLeft` / `dropRight` / `all` / `toFloat` / `fromFloat` / `toUpper` / `trim` / `words` / `lines` / `split` / `replace` / `reverse` / `repeat` / `uncons` / `contains` / `map` / `filter` | official `pad` pads both sides (C uses codepoint length + UTF-8 pad char, not bytes); official `indexes` / `indices` advance by the needle length and report character indices (`"c"` in `"éclair"` is `[1]`); official `indices` is `indexes`; official `left` / `right` for `n < 1` are `""`; official `dropLeft` / `dropRight` for `n < 1` are identity; official `right 2 "Mulder"` is `"er"`; official `dropRight 2 "Mulder"` is `"Muld"`; official `all` on `""` is `True`; official `toFloat` is `_String_toFloat`; official `fromInt` / `fromFloat` are `number + ''` on web and C (not 3-decimal rounding); official `toUpper` / `toLower` / `toLocaleUpper` / `toLocaleLower` / `trim` are JS `toUpperCase` / `toLowerCase` / `toLocaleUpperCase` / `toLocaleLowerCase` / `trim` (C maps Latin-1, Greek, Latin Extended-A, and Cyrillic `а-я` / `ѐ-џ`, and expands `ß` → `"SS"`, `ŉ` → `"ʼN"`, `İ` → `"i̇"`; C `trim` / `trimLeft` / `trimRight` / `words` use official JS `\\s` including NBSP); official `words` is `trim().split(/\\s+/g)` (`words ""` is `[""]`); official `lines` is `split(/\\r\\n|\\r|\\n/g)`; official `split` is JS `str.split(sep)` (empty sep is per character; `split "" ""` is `[]`; a trailing sep keeps `""`); official `replace` is `join after (split before)` so `replace "" "-" "abc"` is `"a-b-c"`; official `reverse` / `repeat n<=0` / `uncons` / `contains ""` / `startsWith` / `endsWith` / `fromList` / `toList` / `cons` / `join` / `concat` / `isEmpty` match elm/core docs; official `map` / `filter` / `foldl` / `foldr` / `any` / `all` match elm/core (`map` `/`→`.` keeps the input Char on the `else` arm, `filter isDigit "R2-D2"` is `"22"`, `foldl cons "" "time"` is `"emit"`) | `wasm_web_string_test.exs` / `runtime_stdlib_gaps_test.exs` |
| `List.take` / `drop` / `range` / `repeat` / `intersperse` / `unzip` / `partition` / `map` / `map2` / `map3` / `map4` / `map5` / `sort` / `sortBy` / `sortWith` / `filter` / `filterMap` / `foldl` / `foldr` / `concat` / `concatMap` / `indexedMap` / `member` / `sum` / `product` / `maximum` / `minimum` / `isEmpty` / `length` / `singleton` / `all` / `any` | official `take` / `drop` for `n <= 0` are `[]` / identity; official `range lo hi` is ascending inclusive; official `repeat` is `Int -> a -> List a`; official `intersperse` keeps the separator; official `concat [[1,2],[3],[4,5]]` flattens; official `concatMap` is `concat (map f)`; official `indexedMap Tuple.pair` pairs 0-based indexes; official `map3` / `map4` / `map5` drop extra elements from longer lists; official `isEmpty` / `length` / `singleton` / `map` / `filter` / `all` / `any` match elm/core; official `foldl (::) [] [1,2,3]` is `[3,2,1]` and `foldr (::)` is identity; official empty `List.sum [] : Float` / `List.product [] : Float` and `List.sum` of a `List Float` (including a typed empty list) keep `TAG_FLOAT`; official `sortWith` is `_List_sortWith` (including `case compare a b of LT -> GT; EQ -> EQ; GT -> LT`); official `append` / `reverse` match elm/core docs; official `member` is `any ((==) x)`; official `sum` / `product` are `foldl (+) 0` / `foldl (*) 1` on `number` (a `List Float` stays Float: `sum [1.5, 2.5] == 4.0`; empty `List Float` is `0.0` / `1.0`); official `product []` is `1`; official `maximum` / `minimum` are `Maybe` via `_Utils_cmp`; official `sort` is `_Utils_cmp` on comparable Int/Float/Char/String/List/tuples | `wasm_web_list_test.exs` / `runtime_stdlib_gaps_test.exs` |
| `Result.withDefault` / `map` / `mapError` / `andThen` / `toMaybe` / `fromMaybe` / `map2` / `map3` / `map4` / `map5` | official `withDefault` returns the Ok / default value of any type (not an Int coerce); Elm `Ok` / `Err` are `tuple2` and compare equal to host `TAG_RESULT`; official `map3` / `map4` keep the first `Err` | `wasm_web_result_test.exs` |
| `Maybe.withDefault` / `map` / `andThen` / `map2` / `map3` / `map4` / `map5` | official `withDefault` keeps any type; Elm `Just` is `tuple2` and host map/andThen peel the payload (not the pair); official `map3` / `map4` / `map5` are Elm, not host builtins | `wasm_web_maybe_test.exs` |
| `Tuple.first` / `second` / `pair` / `mapFirst` / `mapSecond` / `mapBoth` | official pair maps keep non-Int fields; `mapBoth` applies both functions. Official `#3` `compare` / `List.sort` / let-bind / `case (1, 2, 3)` use `TAG_TUPLE3`; int literals in tuple patterns compare as Int values (not heap-handle identity) | `wasm_web_tuple_test.exs` |
| `Basics.degrees` / `radians` / `turns` / `fromPolar` / `toPolar` / `sin` / `cos` / `atan2` / `modBy` / `remainderBy` / `clamp` / `min` / `max` / `identity` / `always` / `not` / `xor` / `negate` / `abs` / `toFloat` / `round` / `floor` / `ceiling` / `truncate` / `isNaN` / `isInfinite` / `logBase` / `sqrt` / `Bitwise.*` | official `degrees n` is `n * pi / 180`; official `radians` is identity; official `turns n` is `n * 2pi`; official `toPolar (x, y)` is `(sqrt (x^2+y^2), atan2 y x)` (C uses `atan2`, not `atan(y/x)`); official `fromPolar (r, t)` is `(r * cos t, r * sin t)`; official `sin (degrees 90)` is `1`; official `atan2 1 0` is `pi/2`; official `modBy` is `_Basics_modBy` (add `modulus` when signs differ: `modBy 4 -5` is `3`, `modBy -4 5` is `-3`); official `remainderBy 4 -5` is `-1`; official `round` is JS `Math.round` (`-1.5` is `-1`); official `not True == False` compares native 0/1 (not constructor-table ids); official `compare 3 1 == GT` / `1 3 == LT` / `2 2 == EQ` uses TAG_ORDER −1/0/1; official `isNaN (0/0)` / `isInfinite (1/0)` match elm/core; `abs(float) < ε` is `f32.lt` (not truncated `as_int`); `Bitwise.shiftRightZfBy` is JS `>>>` | `wasm_web_basics_test.exs` |
| `Char.toCode` / `fromCode` / `toUpper` / `toLower` / `toLocaleUpper` / `toLocaleLower` / `isUpper` / `isLower` / `isAlpha` / `isDigit` / `isOctDigit` / `isHexDigit` | official `fromCode` outside `0..0x10FFFF` is `�`; official `toUpper` / `toLower` are JS `toUpperCase` / `toLowerCase` (C uses the same Latin-1 / Greek / Latin Extended-A / Cyrillic map; `Char.toUpper 'ß'` is the first code point of `"SS"`); official `toLocaleUpper` / `toLocaleLower` are JS `toLocaleUpperCase` / `toLocaleLowerCase` (C uses the same simple map as `toUpper` / `toLower`); official classify helpers are ASCII-only (`isUpper 'Σ'` is `False`; official `isAlphaNum` is `isLower || isUpper || isDigit`) | `wasm_web_char_test.exs` |
| `Browser.Events` mouse/key / `onResize` / `onVisibilityChange` / `onAnimationFrame` / `onAnimationFrameDelta` | `onResize` is `Int -> Int -> msg` (not a tuple) and does not fire on subscribe; `onVisibilityChange` delivers `Visible` / `Hidden`; `onAnimationFrame` is `Time.Posix -> msg`; `onAnimationFrameDelta` is `Float -> msg`; `onClick` / `onMouse*` / `onKey*` are official `Decoder msg` on `document` | `wasm_web_browser_events_test.exs` / `wasm_web_events_test.exs` |
| `VirtualDom.on` / `Html.Events.on*` / `preventDefaultOn` / `stopPropagationOn` / `custom` | `html_cmd` kind 8 + `VirtualDom.Handler` peel | `wasm_web_events_test.exs` |
| `Browser.Dom.focus` / `blur` / `getViewport` / `getViewportOf` / `setViewport` / `setViewportOf` / `getElement` / `setTitle` | Task builtins + `setTitle` `browser_cmd` kind 12; `setViewport` / `setViewportOf` read `Float` args (not handle ids); `focus`/`blur` are `Task Error ()` (`NotFound` when the id is missing) | `wasm_web_browser_dom_test.exs` |
| `Html.map` events | mapper composed at dispatch + real decoder args | `wasm_web_map_events_test.exs` |
| elm-pages multi-route bytes | `pageDataFromJs` on boot + nav | `wasm_web_multi_route_bytes_test.exs` (`:wasm_elm_pages_corpus`) |
| `Sub.none` / `Sub.batch` / `Sub.map` | `dom_sub` + platform managers | boot |
| `Task` / `Process.sleep` / `Process.spawn` / `Process.kill` / `Scheduler` | `Process.sleep` is `Float -> Task x ()`; `spawn` returns a unique `Id`; `kill` cancels that pid's sleep and aborts its `Http.task` and `BackendTask.Http` fetch (not `Task.perform` timers); `Task.sequence` is sequential and fails on the first `Task.fail` | `wasm_web_task_test.exs` |
| `Debug.log` / `Debug.todo` / `Debug.toString` | `log` prints `label: value`; `todo` returns unimplemented (not `0`); official `toString` is `_Debug_toAnsiString` without ANSI (`True`/`False`, `42`, `()`, `"hi"`, `'A'`, `'\\v'`, `[1,2]`, `(3,4)`, `(1,2,3)`, `(1,(2,3))`, `(1,Just 2)`, `Just 1` / `Nothing` / `Ok` / `Err`, `{ x = 3, y = 4 }`, `Idle` / `Ready 3` / `Pair 1 2` / `Just (1,2)`, `<function>`). Official `#3` is `TAG_TUPLE3` (outer pair layout `a` + `#2(b,c)`); `#2` whose second field is a pair prints `(1,(2,3))`. A ctor-tagged tail stays one value. N-ary ctors flatten the payload spine using `constructor_arities` (unary tuple payloads stay one arg). Union tags boxed via `new_ctor_int` so `(3,4)` stays a tuple. Record literals store field names (`record_new_named`) so records are not `<internals>`. Typed `Set` / `Dict` / `Array` print `Set.fromList` / `Dict.fromList` / `Array.fromList` like official kernel tags | `wasm_web_debug_test.exs` / `runtime_stdlib_gaps_test.exs` |
| `Time.now` / `Time.every` / `Time.here` / `Time.utc` / `Time.customZone` / `Time.to*` | `Time.here` is `Task Zone`; official `customZone` default offset and `{ start, offset }` eras (alphabetical record) adjust `toHour` / `toMinute`; official UTC epoch `toSecond` / `toMillis` are `0`; calendar uses zone offset + eras on host and C | `wasm_web_time_test.exs` / `wasm_web_time_every_test.exs` / `wasm_web_kernel_diagnostics_test.exs` |
| `Url.fromString` / `Url.toString` / `Url.percentEncode` / `Url.percentDecode` / `Url.Builder.*` | official `fromString` is the elm/url chomp (`http://` / `https://` only; `:443` stays `Just 443`; userinfo / empty host / no scheme are `Nothing`; query is not percent-decoded); not `new URL()`. Official `percentEncode` is `encodeURIComponent`; official `percentDecode` is `Maybe String` (`Nothing` on a bad escape; `+` is not a space); official `absolute` / `relative` / `crossOrigin` / `custom` (`Absolute` / `Relative` / `CrossOrigin`) / `string` / `int` / `toQuery` match elm/url 1.0.0 join, query encode, and `#fragment` | `wasm_web_url_percent_test.exs` / `wasm_web_kernel_diagnostics_test.exs` |
| `Browser.Navigation` | `pushUrl` / `replaceUrl` / `load` / `back` / `forward` / `go` / `reload` / `reloadAndSkipCache`; `pushUrl` / `replaceUrl` call `history.pushState` / `replaceState`; `load` calls `window.location.assign`; official `reload` / `reloadAndSkipCache : Key -> Cmd` from `Browser.application` init call `location.reload(false)` / `reload(true)`; official `back key n` is `history.go(-n)`; `forward key n` / `go key n` pass the delta through | `wasm_web_navigation_test.exs` / `wasm_web_kernel_diagnostics_test.exs` |
| `Http` | `request` / `get` / `post` → `http_command`; official `timeout : Maybe Float` aborts the fetch and delivers `Http.Timeout`; `riskyRequest` / `riskyTask` use `credentials: include`; `expect*` wrap `Result Http.Error`; `task` / resolvers (`Task.attempt`); `track` delivers `Sending` / `Receiving`; `fractionSent` / `fractionReceived`; `Cmd.map` / `Kernel.Http.mapExpect` compose taggers onto `toMsg`; `Process.kill` aborts a spawned `Http.task` | `wasm_web_http_behavior_test.exs` / `wasm_web_http_map_test.exs` / `wasm_web_http_test.exs` / `wasm_web_task_test.exs` |
| `File.Download` / `File.Select` / `File.toString` / `File.toUrl` / `File.toBytes` / `File.decoder` | `file_*` host; `File.Download.string` clicks `<a download>` with the blob payload; `File.Download.bytes` clicks `<a download>` with encoded `Bytes`; `File.Download.url` clicks `<a href download="">`; `File.Select.file` / `files` open `<input type=file>` (`files` is official `File -> List File -> msg`); empty picker stays silent; `File.toString` / `toUrl` / `toBytes` are Tasks that keep the File until the read finishes; `toBytes` is observed with official `Bytes.Decode.unsignedInt8` | `wasm_web_file_test.exs` |
| `Bytes` / `Json` / `Parser` | `bytes_cmd` (u8/i8/u16/i16/u32/i32/f32/f64/string/bytes + `getStringWidth` / `getHostEndianness` + `Bytes.width` + `write_*` 18–27) / `json_cmd` / `parser_cmd`; official `Parser.int` / `float` / `number` (hex is `0x…` via `{ hex = Just identity }`, not a `Parser.hex` value) / `chompUntil` / `chompIf` / `chompWhile` / `chompUntilEndOr` / `getChompedString` / `getOffset` / `getSource` / `getRow` / `getCol` / `token` / `problem` / `backtrackable` / `andThen` / `lazy` / `commit` / `map` / `symbol` / `keyword` / `spaces` / `|=` / `|.` / `sequence` (`Forbidden` / `Optional` trailing) / `variable` / `loop` (`Loop` / `Done`) / `lineComment` / `multiComment` (`Nestable` / `NotNestable`) / `end`; official `Bytes.Decode.fail` is always `Nothing`; official `Encode.null` is `null` and `Decode.null` succeeds only on JSON null; `Decode.value` / `decodeValue` round-trip a `Json.Encode.Value`; `Decode.array` is `Array a`; `Decode.keyValuePairs` is official object-key order (`cons` then `reverse`); `Decode.dict` / `Encode.dict` / `Encode.set` / `Encode.list` / `Encode.array`; `Decode.oneOf` / `andThen` / `maybe` / `nullable` / `lazy`; official `Decode.oneOrMore` is `list` then `andThen` (empty array is `Err`); `Decode.at` is `List.foldr field` (numeric path segments are field names, not indices); `Decode.index` is the array indexer | `wasm_web_json_test.exs` / `wasm_web_parser_test.exs` / `wasm_web_bytes_test.exs` |
| `Random.generate` | steps official `Generator` (`int` / `float` / `list` / `constant` / `map*` / `andThen` / `pair` / `uniform` / `weighted` / `independentSeed`) with a PCG `Seed` | `wasm_web_random_test.exs` |
| `Regex` (`fromString` / `fromStringWith` / `contains` / `find` / `findAtMost` / `replace` / `split` / `splitAtMost` / `replaceAtMost` / `never`) | `fromString` is `Maybe Regex`; `fromStringWith` reads official `Options` (`caseInsensitive`, `multiline`); `contains` is `Regex -> String -> Bool`; official `never` matches nothing; `find` is `List Match` (unlimited `findAtMost`); `splitAtMost 0` is the original string; `Match` fields are alphabetical (`index`, `match`, `number`, `submatches`) | `wasm_web_regex_test.exs` |
| `Array` | official `empty` / `fromList` / `get` / `set` / `push` / `initialize` / `repeat` / `toList` / `toIndexedList` / `append` / `slice` / `map` / `indexedMap` / `foldl` / `foldr` / `filter` / `isEmpty` / `length`; official `slice` uses `translateIndex` (`n < 0` is `max (len + n) 0`; `from > to` is empty); official `set` out of range is identity | `wasm_web_array_test.exs` |
| `case (Maybe, Maybe[, Maybe])` | Mixed official 2-/3-tuple `Just`/`Nothing` arms peel without a heap tuple (`test_maybe_nothing` per leaf) | `wasm_web_maybe_tuple_test.exs` |
| `case rec of { fields } -> …; _ ->` | Bind-only record patterns are GuardedSwitch (always match); `_` is the official exhaustiveness default | `wasm_web_record_case_test.exs` |
| `Dict` / `Set` / `==` | official `Set.member` / `size` / `isEmpty` / `union` / `partition` / `diff` / `intersect` / `filter` / `map` / `insert` / `remove` / `toList` / `foldl` / `foldr`; `Dict.get` / `update` / `merge` (left/both/right in key order); official `Dict.diff` / `intersect` / `filter` / `map` / `keys` / `values` / `isEmpty` / `member` / `union` / `partition` / `insert` / `remove` / `singleton` / `size` / `foldl` / `foldr`; WASM `==` on Maybe/List/records is `runtime.value_equal` (not handle identity); host peels `TAG_MAYBE` vs Elm `Just`/`Nothing` | `wasm_web_set_dict_test.exs` / `wasm_web_string_test.exs` |
| Pebble UI/Cmd/Events | **not in web graph** | dispatcher filter + plan guards |

CI smoke:

```bash
export TEST_ULIMIT_V_KB=6291456 ELIXIR_ERL_OPTIONS="+S 1:1 +MMscs 256"
./scripts/mix-test-limited.sh elmc test/wasm_web_*_test.exs
./scripts/mix-run-limited.sh elmc test/support/check_elm_pebble_dev_wasm.exs
```

Small web fixtures compile with `wasm_strict: true` by default. Minified web manifests keep `functions` / `skipped` / `plan_coverage` on the debug sidecar; `wasm_strict` reads that sidecar so a skipped `Main.main` is a compile error, not an empty module.

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

RC epilogues use C-shaped LIFO `runtime.release` on `owned[]` (newest slot
first). Transferring ops (`tuple2` / `list_cons` / `list_append` /
`make_closure` / `cmd_map` / `sub_map` / platform `html_cmd` / `dom_sub` /
`browser_cmd` / `json_cmd` / `bytes_cmd` / `parser_cmd`) null consumed shadows
so `$fn_out` is not released. TCO restarts skip leftover pointers that are
pointer-equal to a restarted param. Host `release_unless_reachable*` is not
part of the emit path. `immortalizeProgramConfigClosures` stays only for
elm-pages ProgramConfig copies at boot. `union_tag_as_int` / `tuple_proj`
also accept **cmd-shaped** 2- or 3-field records as `(tag, payload)` so
`Cmd.batch` / `Cmd.map` match the same arms as `TAG_TUPLE2`. A domain record
whose first field is an `Int` is not treated as a union tag. `cmd_map` always
keeps the tagger (same as `sub_map`). `html_cmd` kinds 0–14 are implemented;
kind 15 (`custom`) is reserved for host-allocated WebGL widgets. Unknown
`html_cmd` / `browser_cmd` kinds return unimplemented (not a silent `Cmd.none`).
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
  (see `wasm_port_incoming_test.exs`); boot can deliver `opts.incomingPorts` and re-run update/view.
  A payload that arrives before a subscriber is installed is queued (cap 16) and
  flushed when subscriptions register — `sendIncomingPort` no longer returns RC 100
  for a missing subscriber (see `wasm_pending_incoming_port_test.exs`).
  Generic missing-callee stubs emit `missing_callee_stub` and fail `wasm_strict`.
- `Sub.map` / `Sub.batch` and `Cmd.map` / `Cmd.batch` build platform manager records in WASM;
  the JS host walks that tree after subscriptions run to register incoming port handlers with
  composed taggers (identity port callbacks plus outer `Sub.map` functions).
  `Cmd.batch` drains concurrently (`Promise.all`) so one in-flight `Http.task` does not
  block `Process.sleep` or `Http.cancel` in the same batch.
- `Json.Decode` / `Json.Encode` lower to direct `runtime.json_decode_*` / `runtime.json_encode_*` imports (see `wasm_web_json_test.exs`, `wasm_web_json_decode_error_test.exs`); structured `Json.Decode.Error` values use manifest `constructor_tags`. Official `errorToString` is elm/json `errorToStringHelp`: `Failure` is `tuple2(msg, json)` and prints `Problem with the given value:` plus `Encode.encode 4`; `Field` / `Index` prepend `.name` / `['x']` / `[i]`; empty `oneOf` is `Ran into a Json.Decode.oneOf with no possibilities!`; a single failure unwraps; two or more is `Json.Decode.oneOf failed in the following N ways:`. Official `Encode.encode n` is `_Json_encode`: `JSON.stringify(unwrap, null, n) + ''` (indent `> 0` uses `": "` after object keys; empty `{}` / `[]` stay compact). Official `errorToString` then `indent`s that (`String.split "\\n"` / join `"\\n    "`). C decode builds the same `Field` / `Index` / `OneOf` / `Failure` values (official `_Json_expecting` messages, missing-field Failure, parse `This is not valid JSON!`) and pretty-prints Failure JSON the same way (`wasm_web_json_decode_error_test.exs`, C `json_runtime_test.exs`)
- `Elm.Kernel.Bytes` lowers to `runtime.bytes_cmd` for decode/encode/width/read primitives (`read_i8` / `read_i16` / `read_i32` / `read_u16` / `read_f32` / `getStringWidth` / `getHostEndianness` plus the existing u8/u32/f64/string/bytes reads)
  (see `wasm_web_bytes_test.exs`); host can build bytes via `helpers.bytesFromList([...])`. `Bytes.getHostEndianness` is a `Task` that succeeds with the `LE` or `BE` ctor the app passed. Official `Bytes.Decode.andThen` / `loop` / `succeed` / `map` / `fail` compile as Elm `Decoder` steps (see the loop and fail fixtures in `wasm_web_bytes_test.exs`). Host `bytes_cmd` / `json_cmd` / `parser_cmd` take the kind as a raw i32 (same as `html_cmd`) so handle-id collision cannot rewrite the opcode.
- `Browser.Dom.getViewport` / `getViewportOf` / `getElement` build records in official declaration order: scene `[width,height]`, viewport/element `[x,y,width,height]`, Element outer `[scene, viewport, element]`. Inferred (unannotated) access of those inner records must read the same layout (see `wasm_web_browser_dom_test.exs`)
- `Html.Events` / SVG `nodeNS` lower to `runtime.html_cmd` kinds 7–8 (see `wasm_web_events_test.exs`, `wasm_web_svg_test.exs`). `Svg.Attributes` helpers that are official `VirtualDom.attributeNS ns local` emit `html_cmd` kind 20; the host calls `setAttributeNS` with those IR literals (not a guessed `xlinkHref` name). Official `xmlSpace` is `attributeNS` on the XML namespace (`xml:space`). `Svg.Keyed.node` is official `VirtualDom.keyedNodeNS ns`; emit prepends that IR namespace (`html_cmd` kind 10). `preventDefaultOn` / `stopPropagationOn` / `custom` wrap `VirtualDom.Handler`; the host peels `(msg, Bool)` / `{ message, preventDefault, stopPropagation }` (alphabetical fields) and calls the DOM APIs (see `wasm_web_html_test.exs`). Official `onInput` is `stopPropagationOn` + `target.value`; `onSubmit` is `preventDefaultOn`; `onCheck` decodes `target.checked` on `change`.
- `Html.Attributes.property` / `boolProperty` (`checked`, `hidden`, `disabled`) / `stringProperty` (`value`) store the official `Json.Value` as a JS property (bool/int/string/null), not `stringValue` (which dropped `Json.bool` to `""`). `Html.Attributes.style` is official `String -> String -> Attribute` and merges each CSS property onto the node (`el.style.setProperty`) so a second `style` does not overwrite the first. See `wasm_web_html_test.exs`. Browser boot infers 0-arg `init`/`view` from the handle tag/arity (value, `(model, Cmd)`, or closure), not guessed field names.
- `Html.Attributes.map` / `VirtualDom.mapAttribute` lower to `html_cmd` kind 21. Event facts keep the tagger; other attributes pass through (official). See `wasm_web_map_attribute_test.exs`.
- `Task.perform` / `attempt` / `onError` / `mapError` / `map3`–`map5` / `sequence` / `Time.now` / `Time.every` / `Time.here` (`Task Zone`) / `Time.getZoneName` (`Task ZoneName`: official `Name` from `Intl`, else `Offset` with JS `getTimezoneOffset()` minutes west) / `Time.utc` / `Time.customZone` / `Time.toHour`–`toWeekday` / `Time.posixToMillis` lower to `runtime.task_*` / `runtime.time_*` / `runtime.dom_sub`. Official `Time.every` is `Float -> (Posix -> msg) -> Sub msg`: it does not fire on subscribe, delivers `Posix` (`Date.now` millis), and the host retains `toMsg` until unsubscribe (see `wasm_web_time_every_test.exs`). Official `Time.toMonth` / `toWeekday` are nullary `Month` / `Weekday` constructor tags (declaration order, 1-based fallback). Unix epoch UTC is `Jan` / `Thu` / `1970` / `1` and `== Jan` (see `wasm_web_time_test.exs`). Official `Task.attempt` is `andThen (succeed << Ok) >> onError (succeed << Err) >> perform` so a failed task delivers `Err x`, not `Ok (Err x)`. Official `Task.mapError` is `onError (fail << func)`: a failed task applies `func` then `Task.fail`; a succeeding task is unchanged (see `wasm_web_task_test.exs`). `Task.perform` returns a drainable `TAG_CMD` so `Cmd.map` composes after the task `toMsg` (see `wasm_web_task_test.exs`, `wasm_web_time_test.exs`)
- `Json.Decode.map8` lowers with map1–7 and fills an 8-field record in declaration order (see `wasm_web_json_test.exs`); `Json.Decode.value` / `decodeValue` keep a `Json.Encode.Value` that `Encode.encode` can print; `Json.Decode.array` is `Array a`; `Json.Decode.keyValuePairs` is `List (String, a)` in object key order (official `cons` then `List.reverse`); `Json.Decode.dict` is official `map Dict.fromList (keyValuePairs decoder)` (see `wasm_web_json_test.exs`); `Json.Encode.dict` / `Encode.set` lower to `runtime.json_encode_dict` / `json_encode_set`; `Regex.fromString` (`Maybe Regex`) / `fromStringWith` / `find` (`List Match`) / `findAtMost` / `split` / `splitAtMost` / `replaceAtMost` lower to `runtime.regex_*`. Host `Match` records use alphabetical fields (`index`, `match`, `number`, `submatches`); leftover `regex_find` is unlimited `findAtMost` (see `wasm_web_regex_test.exs`)
- `Url.fromString` (`Maybe Url`) / `Url.toString` / `Url.percentEncode` / `Url.percentDecode` / `Url.Builder.absolute` / `relative` / `crossOrigin` / `custom` / `string` / `int` / `toQuery` lower to `runtime.url_*` (the previous `Url.Builder.crossOrigin` → `"anonymous"` rewrite is gone). Official `fromString` is the elm/url chomp (`http://` / `https://` only; `:443` stays `Just 443`; userinfo / empty host / no scheme are `Nothing`), not `new URL()`. Official `custom Relative` is not a leading slash: `Root` is a mixed union, so nullary `Absolute` / `Relative` are `tuple2(tag, ())` and only `CrossOrigin` has a String payload. Official `percentEncode` is `encodeURIComponent`. Official `percentDecode` is `Maybe String`: invalid `%` escapes are `Nothing`, and `+` stays `+` (see `wasm_web_url_percent_test.exs`)
- `Html.Events.targetValue` / `targetChecked` / `keyCode` rewrite to `Json.Decode.at` / `field`
- `Browser.Events.onVisibilityChange` delivers `Visible` / `Hidden` constructor tags (declaration order, not 1/0)
- `Random.generate` lowers to `runtime.random_generate` (web cmd, not Pebble encoding). The host peels `Generator (Seed -> (a, Seed))`, steps official `initialSeed` PCG state, and applies `toMsg` to the value. Official `andThen` / `pair` / `uniform` / `weighted` compile as Elm and step through that same generator (`wasm_web_random_test.exs`)
- `Elm.Kernel.Regex.*` lowers to `runtime.regex_*`. Official `Regex.contains` is `Regex -> String -> Bool`; official `Regex.never` matches nothing (`wasm_web_regex_test.exs`)
- `Browser.Events` / `Browser.Navigation` (`pushUrl` / `replaceUrl` / `load` / `back` / `forward` / `Elm.Kernel.Browser.go` / `reload` / `reloadAndSkipCache`) / `Browser.Dom` lower through `dom_sub` / `browser_cmd` / Task builtins. `back` / `forward` take official `Key -> Int -> Cmd` and the host uses `history.go` (signed delta).
- Structural `==` / `compare` for records, lists, unions, Dict/Set keys in the JS host. WASM `:value` equality calls `runtime.value_equal` (C already used `elmc_value_equal`); host `TAG_MAYBE` equals Elm `Just` / `Nothing` constructors.
- `Http.get` / `post` / `request` / `riskyRequest` / `task` / `riskyTask` / `expectString` / `expectJson` / `expectBytes` / `expectWhatever` / `expectStringResponse` / `expectBytesResponse` / `stringResolver` / `bytesResolver` / `emptyBody` / `header` / `stringBody` / `jsonBody` / `bytesBody` / `fileBody` / `multipartBody` / `stringPart` / `filePart` / `bytesPart` / `Http.expect` / `Kernel.Http.mapExpect` / `track` (`Sending` / `Receiving`) / `fractionSent` / `fractionReceived` lower to `runtime.http_*` imports; init/update cmds drain via the host boot loop. Official `timeout : Maybe Float` aborts with `AbortError` and delivers `Http.Timeout`. Official `Http.expectJson` runs the `Json.Decode` decoder on the response body and wraps `Ok a` / `BadBody`. Official `Http.expectBytes` runs `Bytes.Decode` on the `arrayBuffer` body; `expectWhatever` succeeds with `()`; `multipartBody` / `stringPart` / `bytesPart` become `FormData`. Official `Http.expectStringResponse` / `expectBytesResponse` / `stringResolver` / `bytesResolver` case on `Response` constructors from the manifest (`GoodStatus_` is `Metadata` + body; `BadStatus_` is `Metadata` only — trailing underscore so they do not collide with `Http.Error`). Bytes variants deliver a host `Bytes` body that official `Bytes.Decode` / `Bytes.width` can read. `Http.header` / `stringBody` on `Http.task` become fetch headers and a MIME body; official `jsonBody` is `Encode.encode 0` with `application/json`; `bytesBody` sends host `Bytes` with the given MIME; official `fileBody` / `filePart` send a selected `File` (empty MIME so the File type is used); official `riskyRequest` / `riskyTask` use `credentials: "include"`. `Metadata` fields are declaration order (`url`, `statusCode`, `statusText`, `headers` as `Dict String String`) (see `wasm_web_http_test.exs`). `Cmd.map` keeps the tagger (same as `Sub.map`) and the host applies it after expect `toMsg` (see `wasm_web_http_test.exs`, `wasm_web_http_map_test.exs`)
- `BackendTask.Http` client requests (`get`, `getJson`, `getWithOptions`, `post`, `request`, body/expect helpers, `withMetadata`) lower to `runtime.backend_task_http_*` imports and run in the browser via `fetch` (see `wasm_web_backend_task_http_*_test.exs`). Task failures use typed `BackendTask.Http.Error` constructors when present in the manifest `constructor_tags` map (`BadStatus`, `Timeout`, `NetworkError`, `BadBody` with structured `Json.Decode.Error` values when those tags are available). Nested `withMetadata` chains combine inner-to-outer against one response metadata record. Server-only elm-pages cache (`cacheStrategy` / `cachePath`) is ignored at runtime; compile emits warning `browser_http_cache_ignored` when those fields are `Just` in a `getWithOptions` literal.
- `File.Download.string` / `bytes` / `url`, `File.Select.file` / `files`, `File.decoder` (`runtime.file_decoder`), and `File.name` / `mime` / `size` / `lastModified` / `toString` / `toBytes` / `toUrl` lower to `runtime.file_*`. `File.Download.string` clicks `<a download>` with the blob; `File.Download.bytes` uses the same cmd with a `Bytes` blob; `File.Download.url` clicks `<a href download="">`. `File.Select.file` is `File -> msg`; official `files` is `File -> List File -> msg` (first + rest). An empty/canceled picker does not send a msg. `File.toString` / `toUrl` / `toBytes` return Tasks; the host retains the File until the async read completes (Node without `FileReader` uses `arrayBuffer` + `data:` base64 for `toUrl`). `toBytes` yields a host `Bytes` that official `Bytes.Decode` can read. `File.decoder` accepts native `File`; `Decode.list` / `array` / `index` treat `FileList` as an array (see `wasm_web_file_test.exs`)
- Route record field access stays reachable under web DCE (see `wasm_web_route_field_test.exs`)
- `Elm.Kernel.Parser.isSubString` / `isSubChar` / `isAsciiCode` / `chompBase10` / `consumeBase` / `consumeBase16` / `findSubString` lower to `runtime.parser_cmd` (see `wasm_web_parser_test.exs`); package-private
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
