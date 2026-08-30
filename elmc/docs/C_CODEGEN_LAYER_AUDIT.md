# CCodegen layer audit (plan-primary vs legacy body)

Plan-primary (`plan_ir_mode: :primary`) is the **production** Pebble codegen path.
This document classifies `Elmc.Backend.CCodegen.*` so we know what can be deleted
vs what must be kept or migrated.

See also: [PLAN_IR_COVERAGE.md](PLAN_IR_COVERAGE.md), [plan/README.md](../lib/elmc/backend/plan/README.md).

## Summary

| Layer | Removable? | Notes |
|-------|------------|-------|
| **Fragment IR→C** (`DirectRender.Emit.ExprDispatch`, `CaseCompile`, …) | **No** | DirectRender/scene operands via `Operand` → `ExprDispatch`; `Host.compile_expr` routes to same dispatcher |
| **Plan C lower** (`C.Lower.*`) | No | Primary emitter; lives outside `c_codegen/` |
| **Function shells / orchestration** (`FunctionEmit`, ABI, `RcRequired`) | No | Wraps plan bodies, fusion, native helpers |
| **Fusion matchers** | No (relocated) | `Elmc.Backend.Plan.Fusion.Matchers.*`; registry in `Plan.Fusion.Registry` |
| **Direct render** (`DirectRender.*`) | Partial | Selection + `CommandDef` shell; bodies via **Plan stream SSA** (`Plan.Stream` → `C.Lower.emit_core` + `direct_scene_push`) with `Emit.Expr` / `ExprDispatch` fallback |
| **SpecialValues** (Cmd/Sub/Pebble rewrites) | No (relocated) | `Plan.Lower.SpecialValues.*` handlers |
| **Project / pebble glue** (`ProjectWriter`, `Emit`, macros) | No | Always needed for `elmc_generated.c` |

**Do not delete the `c_codegen/` directory wholesale.** The legacy `legacy_body/` subtree is removed;
fragment compilation lives under `DirectRender.Emit.ExprDispatch` and shared `*_compile` modules.

## Fragment dispatch (2026-07)

- `DirectRender.Emit.Operand` — DR entry with `ValueSlots.transfer/1` take marking
- `DirectRender.Emit.ExprDispatch` — IR→C fragment dispatcher (formerly `LegacyBody.ExprCompile`)
- `Host.compile_expr` — sets `__direct_render_emit__`, delegates to `ExprDispatch` (or `Operand` when take-marking)
- `TailRecursiveLoopEmit` — fusion `while (1)` helper emission (no `FunctionEmit`/`Host` body debt)
- `DirectRender.Emit.BoxedOperand` — native demotion boxed subexpr helper (no `Host.compile_expr`)

## Production vs test defaults

| Context | `plan_ir_mode` | `plan_ir_strict` |
|---------|----------------|------------------|
| IDE / `SizeProfile` | `:primary` | `true` |
| `Plan.Defaults` / `Elmc.compile/2` default | `:primary` | `true` |
| `mix test` (`test_helper.exs`) | `:primary` | `true` |
| `PrimaryCodegenCase` / harness tests | `:primary` | `true` |
| Explicit unknown / legacy `:off` | `:primary` (normalized) | per opts |

Unknown mode values normalize to `:primary`.
Strict `:primary` raises on `plan_primary_fallback` / `plan_primary_gap` (no silent gap bodies).

## Code paths in `FunctionEmit`

```
emit_function_def
  plan_ir_mode == :primary  →  emit_boxed_function_def → maybe_emit_primary_plan_body
                                                      → C.Lower.Function.emit(plan)
                                                      → on :legacy → unsupported stub + plan_primary_fallback

  plan_ir_mode == :shadow   →  shadow_verify + same primary emit (no legacy fallback)

  plan_ir_mode == :off      →  normalized to :primary (+ plan_ir_mode_off_removed diagnostic)
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

## Fragment compiler modules (keep — used by ExprDispatch)

Shared `*_compile` modules back `DirectRender.Emit.ExprDispatch` and native peel paths:

| Module | Role |
|--------|------|
| `ExprDispatch` | IR expr → C statements (DR fragment root) |
| `CaseCompile` | `case` → C switch/if chains |
| `RecordCompile` | record update/get in fragment bodies |
| `CallCompile` / `FunctionCallCompile` | calls in fragment bodies |
| `VarCompile`, `LiteralCompile`, `CollectionCompile` | expression leaves |
| `PipeChainCompile`, `LetRecCompile`, `CompareCompile` | control/data |
| `CmdCompile`, `RenderCmdCompile` | platform cmds in DR/scene paths |
| `ConstructorTagCase`, patterns | case specialization |
| `Patterns`, `IfCompile`, `VarArithCompile` | fragment helpers |

## Infrastructure (always keep)

- `ProjectWriter`, `GeneratedSource`, `BuildArtifacts`, `PerModuleArtifacts`
- `Emit`, `Constants`, `UnionMacros`, `RecordFieldMacros`, `ResourceSlotMacros`
- `StackEstimate`, `Types`, `CSource`
- `Subscriptions` (worker/sub IR rewrite + layout analysis input)
- `MacroReachability`, `LinkedBinaryReport`, `DebugProbes`
- `FunctionSplit`, `Hoist`, `EnvBindings`, `OwnershipTransfer`
- `PlatformStatic`, `ProdMode`

## Direct render (keep; not legacy)

`DirectRender.*` is a **size/perf lane** that inlines view/scene command streams.
It runs under plan-primary (`direct_render_only`, `prune_direct_generic`,
`SizeProfile`) and shares analysis with `PrimaryCoverage`.

**Body emit (2026-07):** `CommandDef` tries `DirectRender.PlanStreamEmit` first:

1. Verified Plan stream SSA (`Plan.Stream.lower_function` + `elmc_direct_scene_writer` scene push), including `:stream_for_each`, `:stream_static_draw_table`, and `:stream_affine_text`
2. Legacy `Emit.Expr` / `ExprDispatch` fallback with `plan_stream_fallback` diagnostic

Not a replacement for Plan IR on `update`/`init`; it supersede-emits view helpers while
keeping compact scene-writer push (no boxed `List RenderOp` tails).

## Worker / subscriptions host glue

App `subscriptions()` bodies are Plan SSA (`:pebble_sub` → `elmc_subN`). The TEA host
adapter (`elmc_worker.{h,c}`) uses `Plan.Worker.HostPlan` (not FunctionPlan SSA):

| Piece | Owner |
|-------|--------|
| App `init` / `update` / `subscriptions` bodies | FunctionPlan → C.Lower |
| TEA host shell (`init` / `dispatch` / `compute_subscriptions`) | `Plan.Worker.HostPlan` → `Host.Lower` + `Host.Verify` + `Host.Emit` |
| Pure pending-cmd queue (`elmc_cmd_queue_*`) | `Elmc.Runtime.CmdQueue` → packaged `elmc_runtime` |
| `subscriptions()` / `Sub.batch` IR rewrite | `Plan.Worker.Subscriptions` (+ Plan special-values) |
| Compact slot layout (`sub_tag_slots`, `slot_map`, `frame_slot`) | `Plan.Worker.Layout` |
| Slot table + `apply_sub` / extract+snapshot + subscription runtime C | `Plan.Worker.Emit` |
| Pebble event dispatch + host cmd/view wrappers | `pebble/source_writer/event_dispatch` (`Registry` + `Emit`) |

`Host.Verify` is structural entry-ABI only (not FunctionPlan ownership). HostPlan
does not emit bytecode. `ElmcWorkerState` field renames / 32/16 compact thresholds
remain frozen.

**Layout ABI:** `sub_tag_slots`, `button_raw_subs`, `slot_map`, `frame_slot`,
`model_dependent?`, `compact` (fallback 32/16 when not compact).

**Diagnostics:** `dynamic_subscription_layout` (`elmc/subscriptions`) and
`unsupported_sub` only — no silent `Sub.none`.

**Msg seed order:** `Worker.write_worker_adapter` runs before full C codegen;
`Plan.Worker.Layout` seeds `:elmc_pebble_msg_names` for compact analysis.

## Recommended removal sequence

1. **Inventory `:off` usage** — `grep plan_ir_mode: :off`, `LegacyCodegen`, `emit_legacy_boxed_body`. ✅
2. **Shadow / off emit split** — `:shadow` and `:primary` emit plan bodies only; `:off` uses legacy body (no plan fallback). ✅
3. **Migrate legacy-only tests** — add `LegacyCodegenCase` to modules asserting legacy C shapes (`c_codegen_patterns_test`, …); then flip `test_helper.exs` to `:primary`.
4. **Migrate or drop parity tests** that compared both paths (`plan_parity`). ✅
5. **Delete legacy body** — `legacy_body/ExprCompile` removed; dispatcher is `DirectRender.Emit.ExprDispatch`. ✅
6. **Migrate SpecialValues** — one handler at a time to `Plan.RuntimeBuiltins` + `Plan.Lower.Platform.Pebble`.
7. **Optional rename** — `CCodegen` → `Backend.C` or split `Backend.Fusion` / `Backend.DirectRender`.

## Verification commands

```bash
export TEST_ULIMIT_V_KB=6291456 ELIXIR_ERL_OPTIONS="+S 1:1 +MMscs 256"

# Strict template gate (46 templates; tagged :slow)
./scripts/mix-test-limited.sh elmc test/plan_template_strict_gate_test.exs --include slow

# Reachable coverage (all strict templates, one process per template)
./scripts/mix-test-per-template.sh test/plan_reachable_coverage_test.exs

# Default unit smoke (`:slow` and corpus tags already excluded)
./scripts/mix-test-limited.sh elmc
```

## Current gate status (2026-07)

- **46/46** strict templates pass (`plan_template_strict_gate_test.exs`)
- **13/13** rc_track strict fixtures pass
- Excluded-corpus elmc suite green after plan-primary harness fixes
- IDE compiles with `plan_ir_mode: :primary` only
