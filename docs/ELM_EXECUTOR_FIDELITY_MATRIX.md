# ElmExecutor Runtime Fidelity Matrix

This matrix tracks executor-level semantic coverage for `elm_executor` and is used by
the mixed parity gate (executor fixtures + debugger parity smoke).

## Current Coverage

| Area | Status | Notes |
| --- | --- | --- |
| Message operation resolution (`set`/`inc`/`dec`/`toggle`/`enable`/`disable`/`reset`) | partial | explicit message + core-ir branch hints + structured constructor hints from update/core-ir metadata; records operation provenance |
| Constructor pattern extraction (`constructor`, nested/aliased/tuple/list/cons shapes) | partial | constructor discovery now traverses nested pattern trees |
| Scalar literal inference (`int`/`bool`) for branch defaults | partial | int/bool literal fallback and `if` compare fallback supported |
| `let_in` + compare evaluation for branch boolean defaults | partial | reduced evaluator supports bound vars and compare inside `let_in`/`if` |
| Model key targeting (numeric/bool) with deterministic hint precedence | partial | constructor/field/var/name hints + primary fallback source labels |
| View tree continuity for cursor stepping | partial | parser/init base + deterministic runtime step marker |
| Core IR + metadata propagation in debugger runtime path | partial | optional `elm_executor_core_ir`/`elm_executor_metadata` now flow through debugger/runtime adapters when present; compile bridge storage is best-effort and backend-dependent |
| Parser-expression bridge (`tree_node_to_expr` -> evaluator) | partial | supports field access, tuple selectors, and integer call reductions (`modBy`, arithmetic) where parser nodes carry enough structure |
| Protocol event direction across surfaces | partial | watch, companion/protocol, and phone directions supported |
| Full Elm expression evaluation (`case`, lambda, function calls, collection transforms) | gap | still not a full interpreter; only reduced subset used for mutation hints/defaults |
| Full Elm data/path update semantics (records/lists/tuples) | gap | currently heuristic key mutation, not structural evaluator parity |

## Parity Gate Expectations

1. **Executor parity:** `elm_executor/test/runtime_semantic_executor_test.exs` must cover newly added semantics.
2. **Debugger parity smoke:** `ide/test/ide/debugger/runtime_executor_parity_test.exs` must preserve output compatibility vs `elmc`.
3. **Determinism:** identical requests yield stable runtime/model/view hashes and provenance fields.
