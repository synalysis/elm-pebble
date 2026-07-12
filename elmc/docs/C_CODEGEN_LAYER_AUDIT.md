# CCodegen layer audit (plan-primary vs legacy body)

Plan-primary (`plan_ir_mode: :primary`) is the **production** Pebble codegen path.
This document classifies `Elmc.Backend.CCodegen.*` so we know what can be deleted
vs what must be kept or migrated.

See also: [PLAN_IR_COVERAGE.md](PLAN_IR_COVERAGE.md), [plan/README.md](../lib/elmc/backend/plan/README.md).

## Summary

| Layer | Removable? | Notes |
|-------|------------|-------|
| **Legacy IR→C body** (`ExprCompile`, `CaseCompile`, …) | **Quarantined** | Only used when `plan_ir_mode: :off` (explicit / `LegacyCodegen`) |
| **Plan C lower** (`C.Lower.*`) | No | Primary emitter; lives outside `c_codegen/` |
| **Function shells / orchestration** (`FunctionEmit`, ABI, `RcRequired`) | No | Wraps plan bodies, fusion, native helpers |
| **Fusion matchers** (2048, tuple2 tables, list search, …) | Migrate later | Plan calls via `Plan.Fusion.Registry`; IR match + `fusion_c` still in CCodegen |
| **Direct render** (`DirectRender.*`) | No (today) | View/scene inlining; cooperates with plan-primary |
| **SpecialValues** (Cmd/Sub/Pebble rewrites) | Migrate incrementally | Facade in `Plan.Lower.SpecialValues` |
| **Project / pebble glue** (`ProjectWriter`, `Emit`, macros) | No | Always needed for `elmc_generated.c` |

**Do not delete the `c_codegen/` directory wholesale.** Delete or quarantine the
**legacy body compiler** subtree once `:off` is test-only.

## Production vs test defaults

| Context | `plan_ir_mode` | `plan_ir_strict` |
|---------|----------------|------------------|
| IDE / `SizeProfile` | `:primary` | `true` |
| `Plan.Defaults` / `Elmc.compile/2` default | `:primary` | `true` |
| `mix test` (`test_helper.exs`) | `:off` (legacy assertions; migrate to `:primary`) | `false` |
| `PrimaryCodegenCase` / harness tests | `:primary` | `true` |
| `LegacyCodegenCase` | `:off` | `false` |

Explicit `:off` emits diagnostic `plan_legacy_codegen`. Strict `:primary` raises on
`plan_primary_fallback` / `plan_primary_gap` (no silent legacy body).

## Code paths in `FunctionEmit`

```
emit_function_def
  plan_ir_mode == :primary  →  emit_boxed_function_def → maybe_emit_primary_plan_body
                                                      → C.Lower.Function.emit(plan)

  plan_ir_mode == :shadow   →  shadow_verify + same primary emit (no legacy fallback)

  plan_ir_mode == :off      →  emit_legacy_codegen_body
                               → fusion special body OR emit_legacy_boxed_body
                               → ExprCompile / CaseCompile / …
```

## Modules referenced from Plan (shared — keep)

These are imported from `lib/elmc/backend/plan/**` or `lib/elmc/backend/c/lower/**`:

### Plan lowering

- `Host`, `TypeParsing`, `RecordFieldMacros`, `Expr` (record shapes)
- `ConstantInt`, `StaticString`, `ResourceUnion`
- `FunctionEmit`, `FunctionCallAbi`, `RcRequired`
- `VarAnalysis`, `ListHofResolve`
- `SpecialValues` (+ `Helpers`) — **facade; target: plan builtins**
- `Native.FunctionCall`, `Native.ListIntSearch`, `Native.TypedReturn`
- `DirectRender.Emit.TextOptions`, `DirectRender.Analysis`
- `GenericReachability`, `IRQueries`
- `Util`

### Plan fusion (`Plan.Fusion.Registry` providers)

- `FilterMapRowDrop`, `FoldlOffsetPatch`, `UnionCaseFourPerm`
- `ListConcatReversedRowSlices`, `RowSliceAdjacentMerge`, `SpawnTileChain`
- `PermuteMergeInversePipeline`, `ListMapStaticIndexAt`, `ReverseFoldlOccupied`
- `Tuple2CaseTable`, `UnionStringCase`, `UnionIntCase`, `UnionIntSuffixCase`
- `MaybeIntStringCase`, `IntStringCase`, `MaybeWithDefaultPickSlot`
- `FusionSupport`, `EnvBindings`

### C lower (`C.Lower.*`)

- `FunctionEmit`, `FunctionCallAbi`, `Fusion`, `RcRequired`, `RcRuntimeEmit`
- `Native.FunctionCall`, `ImmortalStringLiteral`, `RowMajorLayout`, `Util`

## Legacy body compiler (delete candidate)

Used only from `emit_legacy_boxed_body` / `ExprCompile.compile` chain when plan
lowering is not primary. **~15 top-level modules + pattern helpers:**

| Module | Role |
|--------|------|
| `ExprCompile` | IR expr → C statements (legacy) |
| `CaseCompile` | `case` → C switch/if chains |
| `RecordCompile` | record update/get in legacy body |
| `CallCompile` / `FunctionCallCompile` | calls in legacy body |
| `VarCompile`, `LiteralCompile`, `CollectionCompile` | expression leaves |
| `PipeChainCompile`, `LetRecCompile`, `CompareCompile` | control/data |
| `CmdCompile`, `RenderCmdCompile` | platform cmds in legacy path |
| `ConstructorTagCase`, `UnionIntCase`, … | legacy pattern emitters (overlap with fusion) |
| `Patterns`, `IfCompile`, `VarArithCompile` | legacy helpers |

Many **unit tests** under `elmc/test/` call these modules directly (shape
assertions on generated C text). Those tests remain valuable for fusion/pattern
modules; legacy-body-only tests can be retired with `:off`.

## Infrastructure (always keep)

- `ProjectWriter`, `GeneratedSource`, `BuildArtifacts`, `PerModuleArtifacts`
- `Emit`, `Constants`, `UnionMacros`, `RecordFieldMacros`, `ResourceSlotMacros`
- `StackEstimate`, `Types`, `CSource`
- `Subscriptions` (worker/sub lowering)
- `MacroReachability`, `LinkedBinaryReport`, `DebugProbes`
- `FunctionSplit`, `Hoist`, `EnvBindings`, `OwnershipTransfer`
- `PlatformStatic`, `ProdMode`

## Direct render (keep; not legacy)

`DirectRender.*` is a **size/perf lane** that inlines view/scene command streams.
It runs under plan-primary (`direct_render_only`, `prune_direct_generic`,
`SizeProfile`) and shares analysis with `PrimaryCoverage`.

Not a replacement for Plan IR; it supersede-emits some view helpers while
`update`/`init` stay on plan.

## Recommended removal sequence

1. **Inventory `:off` usage** — `grep plan_ir_mode: :off`, `LegacyCodegen`, `emit_legacy_boxed_body`. ✅
2. **Shadow / off emit split** — `:shadow` and `:primary` emit plan bodies only; `:off` uses legacy body (no plan fallback). ✅
3. **Migrate legacy-only tests** — add `LegacyCodegenCase` to modules asserting legacy C shapes (`c_codegen_patterns_test`, …); then flip `test_helper.exs` to `:primary`.
4. **Migrate or drop parity tests** that compared both paths (`plan_parity`). ✅
5. **Quarantine legacy body** — move `ExprCompile`, `CaseCompile`, … to `c_codegen/legacy_body/` or feature-flag behind `plan_ir_mode: :off`.
6. **Migrate SpecialValues** — one handler at a time to `Plan.RuntimeBuiltins` + `Plan.Lower.Platform.Pebble`.
7. **Optional rename** — `CCodegen` → `Backend.C` or split `Backend.Fusion` / `Backend.DirectRender`.

## Verification commands

```bash
export TEST_ULIMIT_V_KB=6291456 ELIXIR_ERL_OPTIONS="+S 1:1 +MMscs 256"

# Strict template gate (46 templates)
./scripts/mix-test-limited.sh elmc test/plan_template_strict_gate_test.exs

# Reachable coverage (all strict templates, one process per template)
./scripts/mix-test-per-template.sh test/plan_reachable_coverage_test.exs

# Excluded-corpus smoke (no corpus OOM)
./scripts/mix-test-limited.sh elmc --exclude corpus --exclude corpus_run \
  --exclude corpus_elmx --exclude corpus_index --exclude fixture_codegen \
  --exclude slow --exclude rc_track_2048
```

## Current gate status (2026-07)

- **46/46** strict templates pass (`plan_template_strict_gate_test.exs`)
- **13/13** rc_track strict fixtures pass
- Excluded-corpus elmc suite green after plan-primary harness fixes
- IDE compiles with `plan_ir_mode: :primary` only
