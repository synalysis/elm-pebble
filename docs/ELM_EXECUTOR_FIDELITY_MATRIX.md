# ElmExecutor Runtime Fidelity Matrix

This matrix tracks executor-level semantic coverage for `elm_executor` and is used by
the mixed parity gate (executor fixtures + debugger parity smoke).

## Current Coverage

| Area | Status | Notes |
| --- | --- | --- |
| Message operation resolution | partial | Real `update` via Core IR; `operation_source` is `core_ir_update_eval` or `update_evaluation_failed` / `unmapped_message` |
| Constructor pattern extraction | partial | Constructor discovery traverses nested pattern trees |
| Scalar literal inference | partial | int/bool literal fallback and `if` compare inside `let_in` |
| Model key targeting | partial | Provenance is `core_ir_delta` on single changed key |
| View tree continuity | partial | Core IR `view` evaluation; empty preview when Core IR missing or eval fails |
| Core IR + metadata in debugger | good | Strict Core IR required on reload/step/init; no parser-only model mutation |
| Parser-expression bridge | removed from debugger preview | Preview uses `derive_view_output_for_runtime_model/2` only |
| Record update / dotted vars | good | Core IR `record_update` bases like `model.player` resolve via dotted var walk |
| Qualified stdlib calls | good | e.g. `String.toUpper` via stdlib builtin registry when not in function index |
| Companion `Phone.outgoing` / `sendPhoneToWatch` in update | partial | Evaluates as `cmd.none`; protocol side effects come from debugger followups |
| Elm record patterns in `case` | good | `kind: :record` and `kind: :alias` patterns match in Core IR evaluator |
| Full Elm expression evaluation | gap | Interpreter subset; unsupported ops fail at runtime |
| Full Elm data/path update semantics | partial | Full `update` when Core IR branch eval succeeds |
| Template corpus (30 templates) | good | MCP bootstrap snapshots including multi-module watchfaces; phone templates require versioned Core IR on companion |

## Parity Gate Expectations

1. **Executor parity:** `elm_executor/test/runtime_semantic_executor_test.exs`
2. **Debugger parity smoke:** `ide/test/ide/debugger/runtime_executor_parity_test.exs`
3. **Template corpus:** `ide/test/ide/mcp/debugger_template_corpus_test.exs --only template_corpus`
4. **Determinism:** identical requests yield stable runtime/model/view hashes

## Debugger strict mode

- `Ide.Debugger.RuntimeExecutor` uses `ElmExecutorAdapter` only (no `mutate_runtime_model` fallback).
- Missing versioned Core IR fails closed with `{:core_ir_execution_failed, reason}`.
- `Ide.Compiler.build_core_ir_artifact/1` is strict-only (no non-strict ingest).
