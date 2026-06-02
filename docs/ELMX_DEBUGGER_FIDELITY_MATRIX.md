# Elmx Debugger Fidelity Matrix

Tracks debugger execution fidelity for the `:compiled_elixir` backend (`elmx` → in-memory BEAM).

## Zero-gap policy

Debugger “complete” means **no tolerated compile/codegen gaps** on shipped templates:

- `ELMX_TEMPLATE_COMPILE_GATE=1` — every `ProjectTemplates.template_keys()` watch + phone root must elmx-compile with **no** `corpus_compile_smoke_failure?` bypass.
- `ELMX_TEMPLATE_CORPUS=1` — init/step corpus must succeed or fail the test (not accept `:unsupported_op`).
- PBW/device builds use **elmc only**; elmx failures are warnings on the compile result, not blockers.

## Current Coverage

| Area | Status | Notes |
| --- | --- | --- |
| In-memory compile + hot reload | good | `Elmx.compile_in_memory/2` → `Loader` → `ModuleRegistry`; no `.ex` read on hot path |
| Execution backend switch | good | `execution_backend: :core_ir \| :compiled_elixir` in IDE config |
| Debugger request contract | good | `CompiledElixirAdapter` uses `elmx_manifest` + `elmx_revision` |
| Elm source overlay | good | `Bridge.load_project_from_sources/2` for editor overlays |
| Pure Elm expressions (M1) | good | `simple_project`, `game-jump-n-run` compile; IR constructor lookup |
| Stdlib / RC runtime | good | `Elmx.Runtime.Stdlib` + `Values`; Basics trig + `Char` case via compile-time emit |
| Pebble surface (draw/view/cmd) | good | `SpecialValues` + `runtime_dispatch`; structural `Pebble.Ui` via emit + `ViewShape` |
| Full template corpus on `:compiled_elixir` | good | `ELMX_TEMPLATE_CORPUS=1` — 161 corpus + 66 parity tests green in CI (`elmx-compiled-elixir`) |
| Pebble.Cmd device/time commands | good | `Pebble.Cmd.getCurrentTimeString` aliases → device stubs |
| elm/core (`Maybe`, `Result`, `Random`, `List`) | good | `QualifiedRewrite` + compile-time `qualified.ex` emit; corpus parity on init/step |
| Pebble time/button subscriptions | good | Compile-time `SubscriptionMasks`; runtime `cmd.subscription.register` for debugger stepping |
| Init + step execution | good | `Executor`, `RuntimeExecutor` + `Request` path tested |
| Dual-run parity vs Core IR | good | `compiled_elixir_template_parity_test` + `compiled_elixir_core_ir_parity_test` on init/step fields |
| Launch context / Platform glue | good | `Elmx.Runtime.LaunchContext` normalize + `launchReasonToInt` |

## Parity Gate Expectations

1. **Full template compile gate (zero-gap):** `ide/test/ide/mcp/debugger_template_compile_gate_test.exs` with `ELMX_TEMPLATE_COMPILE_GATE=1`
2. **Codegen coverage:** `elmx/test/backend_coverage_gate_test.exs` (representative watch + all phone templates)
3. **Qualified-call audit:** `elmx/test/qualified_call_audit_test.exs` (no `Stdlib.qualified_call` fallbacks)
4. **Phone template audit:** `elmx/test/phone_template_audit_test.exs`
5. **Template corpus (compiled):** `ELMX_TEMPLATE_CORPUS=1` on `debugger_template_corpus_*` tests
6. **Release script:** `scripts/debugger_release_gate.sh`

## Default policy

- `execution_backend` defaults to `:compiled_elixir` in `ide/config/config.exs`.
- Set `ELMX_EXECUTION_BACKEND=core_ir` to opt out (IDE `config/test.exs` pins `:core_ir` for most unit tests).
