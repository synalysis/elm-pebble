# Elmx Debugger Fidelity Matrix

Tracks debugger execution fidelity for the `:compiled_elixir` backend (`elmx` → in-memory BEAM).

## Current Coverage

| Area | Status | Notes |
| --- | --- | --- |
| In-memory compile + hot reload | good | `Elmx.compile_in_memory/2` → `Loader` → `ModuleRegistry`; no `.ex` read on hot path |
| Execution backend switch | good | `execution_backend: :core_ir \| :compiled_elixir` in IDE config |
| Debugger request contract | good | `CompiledElixirAdapter` uses `elmx_manifest` + `elmx_revision` |
| Elm source overlay | good | `Bridge.load_project_from_sources/2` for editor overlays |
| Pure Elm expressions (M1) | good | `simple_project`, `game-jump-n-run` compile; IR constructor lookup |
| Stdlib / RC runtime | partial | `Elmx.Runtime.Stdlib` + `Values` for Basics/Maybe/List/Tuple/String |
| Pebble surface (draw/view/cmd) | good | `SpecialValues` + `runtime_dispatch`; structural `Pebble.Ui` via emit + `ViewShape` |
| Full template corpus on `:compiled_elixir` | good | `ELMX_TEMPLATE_CORPUS=1` — 161 corpus + 66 parity tests green in CI (`elmx-compiled-elixir`) |
| Pebble.Cmd device/time commands | good | `Pebble.Cmd.getCurrentTimeString` aliases → device stubs |
| elm/core (`Maybe`, `Result`, `Random`, `List`) | partial | `QualifiedRewrite` mirrors curried `elmc` special_value targets |
| Pebble time/button subscriptions | partial | `Subscriptions` masks + `Events.batch` compile-time OR |
| Init + step execution | good | `Executor`, `RuntimeExecutor` + `Request` path tested |
| Dual-run parity vs Core IR | good | `compiled_elixir_template_parity_test` + `compiled_elixir_core_ir_parity_test` on init/step fields |
| Launch context / Platform glue | good | `Elmx.Runtime.LaunchContext` normalize + `launchReasonToInt` |

## Parity Gate Expectations

1. **Codegen coverage:** `elmx/test/backend_coverage_gate_test.exs`
2. **Conformance bootstrap:** `elmx/test/conformance_scorecard_test.exs`
3. **IDE backend routing:** `ide/test/ide/debugger/runtime_executor_execution_backend_test.exs`
4. **Template corpus (compiled):** `ide/test/ide/mcp/debugger_template_corpus_test.exs` with `@tag :compiled_elixir` when enabled

## Default policy

- `execution_backend` defaults to `:compiled_elixir` in `ide/config/config.exs`.
- Set `ELMX_EXECUTION_BACKEND=core_ir` to opt out (IDE `config/test.exs` pins `:core_ir` for most unit tests).
