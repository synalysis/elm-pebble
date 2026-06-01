# Elmx progress

Track parity with `elmc` C codegen. Update matrix rows as backend support lands.

## Milestones

| Milestone | Status | Notes |
|-----------|--------|-------|
| M0 Scaffold + switch | done | `elmx` package, IDE `execution_backend`, `CompiledElixirAdapter` |
| M1 Pure Elm codegen | done | `Elmx.Backend.ElixirCodegen` + Emit; includes `watchface-poke-battle` full compile |
| M2 Runtime library | done | `Stdlib`, `Values`, `Executor`, `Cmd`, `Followups` |
| M3 Pebble surface | partial | `SpecialValues` + runtime stubs; structural `Pebble.Ui` via cross-module emit + `ViewShape` |
| M4 Debugger in-memory hot-reload | done | `compile_in_memory`, Loader, ModuleRegistry, `Ide.Compiler.build_elmx_artifacts_in_memory/2` |
| M5 Template corpus | done | `ELMX_TEMPLATE_CORPUS=1` → 121 corpus + 57 parity tests green; CI job `elmx-compiled-elixir` in `debugger-strict.yml` |
| M6 elm/core + Pebble parity | partial | Kernel/list/string/math/platform shims; nested case + let-bound calls; `++` runtime |

## IDE integration

- Default backend is `:compiled_elixir` (set `ELMX_EXECUTION_BACKEND=core_ir` to opt out). Test suite pins `:core_ir` in `ide/config/test.exs`.
- Watch compile attaches `elmx_manifest` / `elmx_revision` when compiled backend is active, or when `:attach_elmx_on_compile` is true (enabled in `ide/config/test.exs`).
- `RuntimeExecutor.Request` validates elmx artifacts when backend is `:compiled_elixir`.

## Tests

| Test | Purpose |
|------|---------|
| `elmx/test/simple_project_compile_test.exs` | compile + init |
| `elmx/test/step_execution_test.exs` | update step |
| `elmx/test/followups_test.exs` | cmd followups on init |
| `elmx/test/backend_coverage_gate_test.exs` | no unsupported IR ops in fixture |
| `elmx/test/constructor_lookup_test.exs` | IR-derived union constructor lookup |
| `elmx/test/constructor_emit_test.exs` | constructor emit via SpecialValues + union shape |
| `elmx/test/main_program_test.exs` | worker fields + dead-code roots from `main` IR |
| `ide/test/ide/debugger/compiled_elixir_execute_test.exs` | adapter execute |
| `ide/test/ide/debugger/runtime_executor_compiled_elixir_test.exs` | full `RuntimeExecutor` + `Request` |
| `ide/test/ide/debugger/surface_compile_elmx_test.exs` | surface compile → cache → step with elmx artifacts |
| `ide/test/ide/debugger/compiled_elixir_core_ir_parity_test.exs` | dual-run init `value` parity vs Core IR |
| `elmx/test/launch_context_test.exs` | `LaunchContext` normalize + `launchReasonToInt` |
| `ide/test/ide/mcp/game_jump_elmx_compile_test.exs` | game jump (corpus env) |
| `ide/test/ide/mcp/debugger_template_corpus_compiled_elixir_test.exs` | multi-template corpus |
| `ide/test/ide/mcp/debugger_template_compile_gate_test.exs` | all-template compile sweep |
| `ide/test/ide/debugger/compiled_elixir_template_parity_test.exs` | dual-run init + companion wire-step parity vs Core IR |
| `ide/test/ide/debugger/core_ir_phone_connectivity_test.exs` | Core IR-only `GotConnectivity` step |
| `ide/test/ide/debugger/core_ir_phone_environment_test.exs` | Core IR-only `GotEnvironment` step (`Just`-wrapped sun/moon wire) |
| `ide/test/ide/debugger/core_ir_phone_settings_test.exs` | Core IR-only `LifecycleChanged` / `ConfigurationClosed` phone steps |
| `ide/test/ide/debugger/core_ir_phone_timeline_test.exs` | Core IR-only `GotToken` / `PinInserted` phone steps |
| `ide/test/ide/mcp/debugger_template_compile_gate_test.exs` | `ELMX_TEMPLATE_COMPILE_GATE=1` — all template watch + phone workspaces |
| `elm_executor/test/wire_message_normalize_semantic_test.exs` | wire normalize + semantic `GotConnectivity` step |
| `elmx/test/values_wire_test.exs` | union atom → ctor wire maps; Maybe/Result tuples → wire |
| `elmx/test/datalog_dictation_special_values_test.exs` | `Pebble.DataLog.*` + `Pebble.Dictation.start/stop` |
| `elmx/test/append_emit_test.exs` | Elm `++` via `Core.append/2` (strings and lists) |
| `elmx/test/string_qualified_emit_test.exs` | `String.join` / `contains` / `startsWith` / `endsWith` / `repeat` direct emit |
| `elmx/test/indexed_map_emit_test.exs` | `List.indexedMap` via `Core.indexed_map/2` (curried lambdas) |
| `elmx/test/foldl_emit_test.exs` | `List.foldl` via `Core.foldl/3` + `Core.apply2/3` |
| `elmx/test/map_emit_test.exs` | `List.map` / `filter` / `filterMap` via `Core.apply1/2` |
| `elmx/test/compare_emit_test.exs` | `__neq__` / comparison ops + `((/=) 0)` partial predicates |
| `elmx/test/list_stdlib_emit_test.exs` | `List.foldr`, `repeat`, `member`, `all`, `sort`, `sum`, `sortWith` via `Core` |
| `elmx/test/pebble_ui_runtime_test.exs` | 2-arg `drawVectorSequenceAt` |
| `elmx/test/message_decode_test.exs` | `MessageDecode` for FrameTick JSON, int payloads, `FromPhone` wire + paren msgs |
| `elmx/test/core_result_test.exs` | `Result.andThen` / `mapError` `(function, result)` argument order |
| `elmx/test/json_decode_compose_test.exs` | composable `Json.Decode` (`field`, `at`, `index`, `map2`–`map7`, `list`, `array`, `nullable`, `maybe`, `null`, `andThen`, `oneOf`, `succeed`, `decodeString`, storage/launch-context shapes) |
| `elmx/test/json_encode_qualified_test.exs` | `Json.Encode` (`string`, `int`, `float`, `bool`, `null`, `object`, `list`) via `SpecialValues` + qualified dispatch |
| `ide/test/ide/mcp/compiled_elixir_phone_compile_test.exs` | phone `CompanionApp` compile (6 templates) + init (phone-status, storage, weather-env, calendar, settings, geolocation) |
| `ide/test/ide/mcp/debugger_template_corpus_compiled_elixir_test.exs` | phone steps: companion platform msgs + `LifecycleChanged`, `ConfigurationClosed`, `WebSocketEvent`, etc. |
| `ide/test/ide/mcp/compiled_elixir_phone_compile_test.exs` | phone compile+init: status, storage, weather-env, calendar, settings, geolocation, **websocket**, **timeline** |
| `ide/test/ide/mcp/compiled_elixir_phone_compile_test.exs` | optional `CompanionApp` phone surface elmx compile smoke |
| `elmx/test/storage_special_values_test.exs` | `storageReadString` + `backlight` special-value rewrites |
| `elmx/test/companion_special_values_test.exs` | `Pebble.Companion.Phone.sendPhoneToWatch` → `phone_to_watch` protocol cmd |
| `elmx/test/runtime_dispatch_coverage_test.exs` | every static `elmx_*` from `SpecialValues` has `runtime_dispatch/2` clause |
| `elmx/test/health_kernel_runtime_test.exs` | `Pebble.Health.*` kernel calls emit `cmd.device.health_*` (not `Cmd.none`) |
| `elmx/test/compass_peek_runtime_test.exs` | `Pebble.Compass.current` → `cmd.device.compass_peek` + `GotHeading (Ok heading)` decode |
| `elmx/test/unobstructed_bounds_peek_runtime_test.exs` | `Pebble.UnobstructedArea.currentBounds` → `cmd.device.unobstructed_bounds_peek` + rect decode |
| `elm_executor/test/pebble_watch_peek_builtin_test.exs` | Core IR `compassCurrent` / `unobstructedCurrentBounds` → matching `cmd.device.*_peek` wire |
| `elm_executor/test/pebble_dictation_builtin_test.exs` | Core IR `dictationStart` / `dictationStop` → `cmd.dictation.followup` batch wire |
| `elmx/test/datalog_dictation_special_values_test.exs` | `Dictation.start/stop` → batched `cmd.dictation.followup` rows for debugger stepping |
| `elmx/test/pebble_ui_helper_emit_test.exs` | unqualified `Pebble.Ui` / `Pebble.Cmd` surface calls via `rewrite_unqualified_special` |
| `elmx/test/simple_project_compile_source_test.exs` | `compile_in_memory` Main `view` emits `elmx_ui_window_stack` |
| `elmx/test/special_values_ui_test.exs` | `Ui.group`/`context`, `Time.*` weekdays, `Color.indexed`, Pascal-case text options |
| `elmx/test/special_values_canonical_test.exs` | `Cmd.*` → `Platform.Cmd.*` canonicalization (`none`, `getCurrentTimeString`) |
| `elmx/test/runtime_generator_parity_test.exs` | all 249 `elmc_*` symbols from `c_codegen` have `Intrinsics.Registry` handlers |
| `elmx/test/core_compliance_runtime_test.exs` | full `CoreCompliance` module compile + runtime vs elmc expectations |
| `elmx/test/core_compliance_ir_test.exs` | `CoreCompliance` lowers with no `:unsupported` expression bodies |
| `elmx/lib/elmx/backend/elixir_codegen/emit/qualified.ex` | single source for qualified-call / list / string / bitwise emit (`emit.ex` delegates) |
| `elmx/test/stdlib_qualified_emit_test.exs` | `Dict`/`Array`/`Set`/`Bitwise`/`Task`/`Process` qualified calls emit `Core.*` paths |
| `elmx/test/stdlib_runtime_call_parts_test.exs` | `runtime_call_parts` preserves commas inside nested `runtime_dispatch` args |
| `elmx/test/core_result_test.exs` | `Result.andThen` / `mapError` emit `(function, result)` order via registry + stdlib |
| `elm_ex/test/frontend/let_layout_test.exs` | inline `let` with `in` at EOL splits before parse (Elm layout parity) |

Run corpus: `ELMX_TEMPLATE_CORPUS=1 mix test --only compiled_elixir_corpus` (from `ide/`). CI runs this on every PR via `debugger-strict.yml` (`elmx-compiled-elixir` job).

## Missing vs elmc (remaining)

- ~~Core IR dual-run parity for phone `GotConnectivity` and watch `FromPhone` nested-tuple steps~~ fixed via `CoreIREvaluator.normalize_wire_message_value/2` + tuple2 flat-arg matching
- ~~`GotEnvironment` phone steps~~ wire helpers use `Just` for `Maybe SunInfo`/`MoonInfo`; Core IR + elmx parity on `sunriseMin`/`moonPhaseE6`
- ~~Full RC runtime parity (`elmc` `Runtime.Generator`)~~ — **done**: `Elmx.Runtime.Generator` + `Intrinsics` registry covers all 249 `elmc_*` symbols from `c_codegen`; `runtime_dispatch` / `compile_runtime_call` wired
- ~~`special_values_elmc_conformance_test.exs`~~ — in-scope `elmc` `special_value_from_target` names rewrite via `SpecialValues` / kernel / emit
- ~~`ELMX_TEMPLATE_CORPUS=1` compiled_elixir corpus~~ — **164** tests green (watch + phone steps, init/step/followup parity; re-verified after String/partial emit, ~10 min)
- ~~`Result.andThen` / `Result.map` codegen order~~ — `Intrinsics.Registry` + `Stdlib.runtime_call_dispatch` emit `(function, result)`; fixes `unitsFromString` pipeline on companion storage templates
- ~~`Dict.merge`~~ — `Collections.dict_merge/6` + `Core.apply4/5`; `dict_merge_test.exs`; `c_codegen` 6-arg `Dict.merge` clause
- ~~`Dict.map` / `foldl` / `filter` / `partition`~~ — step fns get `(key, value[, acc])` via `apply2`/`apply3`; `dict_hof_test.exs`
- ~~`Dict.update`~~ — `(Maybe v -> Maybe v)` alter, 3-arg API aligned with `elmc`; `dict_hof_test.exs`
- ~~Partial qualified stdlib~~ — `List.*` HOFs (incl. `foldl`/`foldr`/`member`/`indexedMap`), `Dict.*`, `Json.Decode`; `partial_qualified_emit_test.exs`
- ~~Partial user functions~~ — `function_arities` + `Helpers.partial_application_fun/4` (`&fn/arity` or nested `fn`); `user_partial_emit_test.exs`
- ~~Cross-module partial~~ — `CrossModuleCall.partial_application/3`; `cross_module_emit_test.exs`
- ~~`String.replace` direct emit~~ — `Core.Strings.replace/3` + 2-arg partial; `string_replace_emit_test.exs`
- ~~`String.split` direct emit~~ — `Core.Strings.split/2` + 1-arg partial; `string_replace_emit_test.exs`
- ~~`ConstructorLookup.resolve` empty map~~ — no crash on `%{}` lookup; `constructor_lookup_test.exs`
- ~~Companion `Phone.outgoing` / `registerHandler` cmd_none rewrite~~ — `companion_special_values_test.exs` (runtime `cmd_none`; PKJS in IDE)
- ~~Nested `let_in` (mutual bindings via lambdas)~~ — IIFE emit; `let_in_emit_test.exs`
- ~~`Basics.compare` string ordering~~ — `Core.basics_compare/2` + `List.sortWith` via `elmx_basics_compare`; `basics_compare_test.exs`
- ~~Companion `Phone.outgoing` / `registerHandler`~~ — rewrite + runtime `cmd_none` (matches Core IR; PKJS port wiring is IDE/simulator concern)
- Port/runtime bridge fidelity for `Phone.send` / `sendBridgeCommand` — bridge cmds emit `cmd.companion.bridge`; IDE fulfills in simulator
- ~~`MessageDecode` maps wire `()` to `nil`~~ (`message_decode_test.exs` — `PinInserted (Ok ())`)
- ~~`corpus_phone_step_execute!` accepts optional `current_runtime_model:`~~ (`compiled_elixir_corpus_helpers.exs`)
- Case emit: constructor wildcard branches ordered after specific payloads; unresolved names no longer default to `/0` captures; `kind: :string` / `:int` patterns emit literal matches; plain string-key pairs stay nested in `Ok` patterns (fixes `GotPreference`); `Result.andThen`/`mapError` runtime arg order aligned with `elmc`
- More `qualified_call` targets — narrowed: Dict/Set/Array accessors + common String ops use direct IR emit; rare ops still via `Stdlib.qualified_call` / `runtime_call`
- ~~`ELMX_TEMPLATE_COMPILE_GATE=1`~~ green (watch + phone `CompanionApp` when present)
- ~~Dual-run parity tests vs Core IR on more templates~~ green via `compiled_elixir_template_parity_test.exs` (68+ field/step/init-followup parity tests with `ELMX_TEMPLATE_CORPUS=1`)
- ~~Flip default `execution_backend` to `:compiled_elixir`~~ done (opt-out via `ELMX_EXECUTION_BACKEND=core_ir`)

## Coverage rollup

See `elmx/docs/CODEGEN_COVERAGE_MATRIX.md` and `docs/ELMX_DEBUGGER_FIDELITY_MATRIX.md`.
