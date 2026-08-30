# Elmx Debugger Fidelity Matrix

Tracks debugger execution fidelity. TEA init/update/view runs only through
`elmx` (`CompiledElixirAdapter` → in-memory BEAM). Bytecode is optional plan
smoke (`BytecodeApi` / MCP), not a debugger stepper.

## Zero-gap policy

Debugger “complete” means **no tolerated compile/codegen gaps** on shipped templates:

- `ELMX_TEMPLATE_COMPILE_GATE=1` — every `ProjectTemplates.template_keys()` watch + phone root must elmx-compile with **no** `corpus_compile_smoke_failure?` bypass.
- `ELMX_TEMPLATE_CORPUS=1` — init/step corpus must succeed or fail the test (not accept `:unsupported_op`).
- PBW/device builds use **elmc only**; elmx failures are warnings on the compile result, not blockers.

## Current Coverage

| Area | Status | Notes |
| --- | --- | --- |
| In-memory compile + hot reload | good | `Elmx.compile_in_memory/2` → `Loader` → `ModuleRegistry`; no `.ex` read on hot path |
| TEA execute path | good | elmx only; `execution_backend: :compiled_elixir` is a fingerprint label, not a switch |
| Debugger request contract | good | `CompiledElixirAdapter` uses `elmx_manifest` + `elmx_revision` |
| Elm source overlay | good | `Bridge.load_project_from_sources/2` for editor overlays |
| Pure Elm expressions (M1) | good | `simple_project`, `game-jump-n-run` compile; IR constructor lookup |
| Stdlib / RC runtime | good | `Elmx.Runtime.Stdlib` + `Values`; Basics trig + `Char` case via compile-time emit |
| Pebble surface (draw/view/cmd) | good | `SpecialValues` + `runtime_dispatch`; structural `Pebble.Ui` via emit + `ViewShape` |
| Full template corpus on elmx | good | `ELMX_TEMPLATE_CORPUS=1` — 161 corpus + 66 parity tests green in CI (`elmx-compiled-elixir`) |
| Pebble.Cmd device/time commands | good | `Pebble.Cmd.getCurrentTimeString` aliases → device stubs |
| elm/core (`Maybe`, `Result`, `Random`, `List`) | good | `QualifiedRewrite` + compile-time `qualified.ex` emit; corpus parity on init/step |
| Pebble time/button subscriptions | good | Compile-time `SubscriptionMasks`; runtime `cmd.subscription.register` for debugger stepping |
| Init + step execution | good | `Elmx.Runtime.Executor`, `RuntimeExecutor` + `Request` path tested |
| Launch context / Platform glue | good | `Elmx.Runtime.LaunchContext` normalize + `launchReasonToInt` |
| Bytecode | smoke | `BytecodeApi` / MCP plan smoke only — not a TEA backend |

## Parity Gate Expectations

1. **Full template compile gate (zero-gap):** `ide/test/ide/mcp/debugger_template_compile_gate_test.exs` with `ELMX_TEMPLATE_COMPILE_GATE=1`
2. **Codegen coverage:** `elmx/test/backend_coverage_gate_test.exs` (representative watch + all phone templates)
3. **Qualified-call audit:** `elmx/test/qualified_call_audit_test.exs` (no `Stdlib.qualified_call` fallbacks)
4. **Phone template audit:** `elmx/test/phone_template_audit_test.exs`
5. **Template corpus (compiled):** `ELMX_TEMPLATE_CORPUS=1` on `debugger_template_corpus_*` tests
6. **Release script:** `scripts/debugger_release_gate.sh`

## Default policy

- Debugger TEA is elmx-only. `execution_backend` on runtime fingerprints is the constant `"compiled_elixir"`.
- There is no `ELMX_EXECUTION_BACKEND` / Core IR execute switch.
