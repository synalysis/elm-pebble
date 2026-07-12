# Plan IR coverage

Plan-primary codegen (`plan_ir_mode: :primary`) lowers **reachable** Elm functions to
`%FunctionPlan{}`, verifies ownership, then emits C (and optional bytecode). This
document tracks **generic** coverage — IR shapes and stdlib APIs — not per-template
shims.

See also: [CODEGEN_COVERAGE_MATRIX.md](CODEGEN_COVERAGE_MATRIX.md) (legacy C path),
[plan/README.md](../lib/elmc/backend/plan/README.md) (contract and flags).

## Principles

1. **No app/template gates** — plan lowering keys off IR ops, patterns, and
   `RuntimeBuiltins` ids, never project slug or function name lists.
2. **Poke Battle is a fixture, not a spec** — it stress-tests common watch patterns;
   fixes must work for any app that emits the same IR.
3. **`plan_ir_strict: true`** — every **reachable** function must plan-lower; no
   legacy C fallback. Default in `:primary` mode (IDE dev / size profile).
4. **Prove genericity** — new lowering paths need a focused plan test plus a
   second unrelated fixture or template when the pattern is domain-shaped.

## Strict smoke gate (templates)

`mix test test/plan_template_strict_gate_test.exs` compiles watch templates with
`plan_ir_strict: true`. Templates in `@strict_pass` must compile with **zero**
`plan_primary_fallback` diagnostics and **zero** `elmc_unknown` calls in
`c/elmc_generated.c`.

**Do not** run the full strict gate, reachable coverage, or opcode audit files in
one `mix test` invocation — many template compiles in one BEAM process can exceed
ulimit. Use one template per process:

```bash
export TEST_ULIMIT_V_KB=6291456 ELIXIR_ERL_OPTIONS="+S 1:1 +MMscs 256"
./scripts/mix-test-strict-gate.sh                    # all strict gate templates
./scripts/mix-test-per-template.sh test/plan_reachable_coverage_test.exs
./scripts/mix-test-per-template.sh test/bytecode_opcode_audit_test.exs
./scripts/mix-test-per-template.sh test/plan_fusion_manifest_audit_test.exs
```

`mix test test/plan_rc_track_strict_gate_test.exs` applies the same gates to all
13 elm/core rc_track probe fixtures.

`mix test test/plan_rc_track_probe_execution_test.exs` (alias `mix test.plan_rc`) runs
matrix coverage gates; `mix test.plan_rc_exec` additionally runs host RC balance harnesses
on plan-emitted C (opt-in until plan/native-int ABI matches legacy for all probes).

`mix test test/plan_reachable_coverage_test.exs` asserts strict reachable coverage
for every template in `PlanStrictTemplates`.

`mix test test/bytecode_opcode_audit_test.exs` scans emitted `.elmcbc` sections for
every strict template (`--include slow`) and fails if any opcode byte is unknown or
maps to a plan op not yet implemented in `Bytecode.Runtime`. Quick gate (5 templates)
runs by default; full 46-template sweep is tagged `:slow`.

`mix test test/plan_manifest_execution_smoke_test.exs` runs `Main.init` / `Main.update`
from the bytecode manifest on templates that exercise guarded patterns and list recursion.

`mix test test/plan_yes_bytecode_test.exs` runs fused string helpers and `Main.view`
from the watchface_yes manifest.

`mix test test/plan_core_builtins_test.exs` includes a registry audit: every
quoted `elmc_*` runtime symbol in `special_values/` maps through
`RuntimeBuiltins.from_c_symbol/1`.

| Template | Strict (2026-07) | Notes |
|----------|------------------|-------|
| `game_2048` | pass | |
| `game_elmtris` | pass | |
| `game_basic` | pass | |
| `watchface_poke_battle` | pass | Exercises bool tuple case, 3-way list case, dotted record update, `clamp` / `isEmpty` |
| `watchface_yes` | pass | Large render surface; plan + direct-render |
| `watchface_analog` | pass | |
| `watchface_digital` | pass | |
| `watchface_minimal` | pass | |
| `watchface_weather_animated` | pass | |
| `watchface_tangram_time` | pass | Fixed-length list `case`, `[]` / var list `case`, `List.concat` |
| `companion_demo_storage` | pass | |
| `game_tiny_bird` | pass | |
| `watchface_color_shapes` | pass | |
| `watchface_smoke_screen` | pass | |
| `app_minimal` | pass | |
| `watch_demo_storage` | pass | |
| `companion_demo_weather_env` | pass | |
| `starter_watch` | pass | Companion `requestWeather` / `sendWatchToPhone` (needs `shared-elm` sources) |

Update this table when the gate test list changes.

## Construct coverage (Poke Battle–driven, app-agnostic)

These landed as **generic** toolchain work (any app using the same IR):

| IR / API | Plan path | Limitation |
|----------|-----------|------------|
| `String.isEmpty` | `:string_is_empty` builtin | |
| `String.left` | `:string_left` qualified lowering | `String.right` still via generic `Call` if mapped |
| `Basics.clamp` | `:basics_clamp` + `@c_value_return` | |
| `True` / `False` in `case` patterns | `:test_bool` (`elmc_as_bool`) | Tuple + `GuardedSwitch` |
| `(a, b)` bool tuple `case` | `GuardedSwitch` + `:test_bool` | Needs guardable branch patterns |
| `case` on `[]` / `x :: xs` | `ListSwitch` (2 arms) | Exact branch shape |
| `case` on `[]` / catch-all var | `ListSwitch.compile_empty_var/4` | `[]` + `xs` or `_` |
| `case` on `a :: … :: []` (fixed N) | `ListSwitch.compile_fixed_length_nil/4` | Distinct lengths + default |
| `case` on `x :: y :: _` / `[only]` / `[]` | `ListSwitch.compile_triple/4` | Exactly 3 arms, fixed shapes |
| `case` on `x :: y :: _` + wildcard | `double_cons_wildcard` | 2 arms only |
| `record_update` field expr | `Context.for_branch_arm` for fields | Avoids `:fn_out` in `record_update` value slot |
| Dotted var `model.field` / `a.b.c` | Split → chained `record_get` | Arbitrary depth via `compile_dotted_var_path` |
| `Plan.Verify` phi | Respect `effects.consumes` only | Live locals after merge |

Nothing in this table references Poke Battle modules or slugs.

## Pattern matchers (shape-limited but generic)

Plan `case` dispatch (`Plan.Lower.Case.compile_dispatch/5`) tries, in order:

1. `ListSwitch.fixed_length_nil_branches?` — `a :: … :: []` arms + default
2. `ListSwitch.triple_branches?` — `::` × 2 + singleton + `[]`
3. `ListSwitch.double_cons_wildcard_branches?`
4. `ListSwitch.empty_var_branches?` — `[]` + var / wildcard
5. `ListSwitch.branches?` — `::` + `[]`
6. `TagSwitch` — union / ctor tags
7. `IntSwitch` — literal int arms
8. `GuardedSwitch` — tuple / ctor / int / wildcard patterns
9. `compile_linear_branches` — general pattern fallback (ctor / int / wildcard arms)

**North-star gates (2026-07):** all 46 IDE watch templates in `@strict_pass`, all 13
rc_track elm/core fixtures, `simple_project`, and companion worker fixtures compile
under `plan_ir_strict: true` with zero fallbacks and zero `elmc_unknown`.

**Not yet covered** (examples from other apps / future work):

| Pattern | Example | Likely next work |
|---------|---------|------------------|
| Heavy nested `let_in` + list callbacks | large game `update` | Covered generically; add tests as patterns land |
| `List.map` with record update in lambda | many games | Generic `list_map` + closure body (no fusion required) |

**Recently completed** (generic plan paths):

| IR / API | Plan path |
|----------|-----------|
| `compose_left` / `compose_right` | Desugar to `lambda` in `Expr.compile/3` |
| `String.*` / `List.*` binary stdlib | `@qualified_binary` → `call_runtime` |
| Ternary `String.replace` / `Basics.clamp` | `@qualified_ternary` |
| Other `Module.fn` with arity 3 | `@qualified_ternary` miss → `Call.compile_call` → `:call_fn` (guard `not is_nil(id)` — `nil` is an atom in Elixir) |
| User / helper `Module.fn` (any arity) | `Call.compile_call` → `:call_fn` when not a stdlib map hit |
| `Result.withDefault` | `@qualified_binary` → `:result_with_default` |
| `Task.map` / `Task.map2` / `Task.andThen` | `runtime_call` → `:task_map` / `:task_map2` / `:task_and_then` |
| `Cmd.map` / `Sub.map` | `runtime_call` → `:cmd_map` / `:sub_map` |
| `List.repeat` with literal or foldable count | `fold_list_repeat_literals` → `:const_static_list` when count ≥ 4 and item is a literal int (`ConstantInt` resolves top-level decl refs like `boardSize`) |
| Bytecode VM locals sizing | `max(plan.reg_count, param_count, 1)` — always reserve the `:fn_out` slot |
| Bytecode VM `record_get` field index | C-style macro suffix stripped in encoder |
| Bytecode VM `test_list_empty` / `test_ctor_tag` / `test_bool` | Opcodes 33–35; list `case` branches in manifest execution |
| Bytecode VM `bool_and` | Opcode 36; tuple/ctor guarded pattern conditions |
| Bytecode VM int-list peel | `int_list_head_int`, `int_list_tail`, `list_head`, `list_tail`, `list_is_empty` builtins |
| Bytecode VM opcode audit | 36 opcodes (1–36); all 46 strict templates pass (`bytecode_opcode_audit_test.exs --include slow`) |
| Plan ops not yet in bytecode VM | none for strict templates; `:call_closure`, `:list_cursor_map`, `:forward_ref_*` implemented as opcodes 37–42 |

## Fusion bytecode sidecars

When plan-primary fusion matches (`Plan.Fusion.CEmit`), the C body is emitted as
`fusion_c` and a parallel **bytecode runner** sidecar is attached when the fusion
module implements `extract_fusion_data/4` (or `Tuple2CaseTable.extract_table/1`).
`Bytecode.ProjectWriter` writes these to `fusion_functions` in
`bytecode/elmc_bytecode.manifest.json`; `FusionRunner` interprets them at runtime.

`mix test test/plan_fusion_manifest_audit_test.exs` checks key templates
(`game_2048`, `game_elmtris`, `watchface_yes`) for expected fusion kinds and
regression-tests that every manifest fusion kind has a `FusionRunner` clause.

`mix test test/plan_manifest_execution_smoke_test.exs` runs `Main.init` (and
poke-battle `update`) from bytecode manifests with timeouts — catches missing
VM opcodes (`test_list_empty`, `bool_and`, etc.) that would hang execution.

| Fusion kind | Typical IR / use |
|-------------|------------------|
| `tuple2_case_table` | `(kind, rot)` → list of offset pairs |
| `filter_map_row_drop` | Drop full board rows |
| `foldl_offset_patch` | Stamp piece cells on board |
| `reverse_foldl_occupied` | Locked slot indices from board |
| `list_indexed_replace` | Flat list cell update |
| `list_int_search` | Nth empty cell index |
| `spawn_tile_chain` | Chained `spawnTileWithSeed` on static board |
| `permute_merge_inverse_pipeline` | orient → collapseRows → restore + spawn + model update |
| `list_map_static_index_at` | Static index-at map (transpose) |
| `union_int_lut` / `union_string_lut` / `int_string_lut` | Case-on-tag/string tables |
| `maybe_int_string` / `union_int_suffix` | Maybe-field string formatting |
| `maybe_with_default_pick_slot` | Maybe pick with default |
| `union_case_four_perm` | Four-way direction permute |
| `row_slice_adjacent_merge` | Per-row 2048 merge |
| `list_concat_reversed_row_slices` | Reverse each row slice |

Fused functions must not appear in manifest `skipped` with reason `empty_plan`
(wire metadata missing). `moveBoard` on `game_2048` uses
`permute_merge_inverse_pipeline` (inline spawn; no separate `spawnTileWithSeed`
fusion sidecar).

## Runtime builtins

Plan lowers `runtime_call` and qualified stdlib through
`Elmc.Backend.Plan.RuntimeBuiltins`. Every quoted `elmc_*` symbol emitted by
`special_values/` is registered (main map + `RuntimeBuiltins.Extra`). Unregistered
symbols would emit `elmc_unknown` in generated C — gated by strict template/rc_track
tests.

Qualified stdlib routing lives in `expr.ex` (`@qualified_unary` / `@qualified_binary`
/ `@qualified_ternary`, plus `SpecialValues` rewrite before dispatch). User
`Module.fn` calls lower to `:call_fn` when not a stdlib map hit (see nil-is-atom
guard on ternary/binary maps).

## How to extend coverage

1. Reproduce with `plan_ir_strict: false`, then `Function.lower/4` on the decl
   (`TemplateCompile.decl_map_from_result/1`).
2. Identify failing op (`Expr`, `Case`, `Record`, `Call`, `let_in`, …).
3. Implement **generic** lowering; add `elmc/test/plan_*_test.exs` with minimal IR
   or a second template.
4. Add template to `@strict_pass` in `plan_template_strict_gate_test.exs` when it
   compiles strict with zero fallbacks.
5. For list/case patterns, prefer extending `ListSwitch` / `TagSwitch` with
   **structural** detectors (branch count, ctor names `::` / `[]`), not domain
   literals from one app.

## Diagnostics

| Code | Strict? | Meaning |
|------|---------|---------|
| `plan_primary_fallback` | error | Reachable function used legacy C body |
| `plan_primary_gap` | error | Reachable function not plan-eligible |
| `plan_primary_coverage` | info | Stats when primary succeeds |
| `plan_legacy_codegen` | info | Explicit `plan_ir_mode: :off` |

`Elmc.Backend.Plan.PrimaryCoverage` aggregates reachable/Main lowering stats on
compile results (`layout_coercion_diagnostics`).

## Relation to “all possible apps”

- **Strict pass on a template** = all reachable functions in *that* app plan-lower.
- **Full Elm** = strict pass on every valid app — requires completing the matrices
  above, not more template tuning.
- Legacy C body codegen remains available only with explicit `plan_ir_mode: :off` (tests via `Elmc.TestSupport.LegacyCodegen`).

See [C_CODEGEN_LAYER_AUDIT.md](C_CODEGEN_LAYER_AUDIT.md) for which `CCodegen` modules are legacy-body-only vs still required under plan-primary.

IDE production builds use `plan_ir_mode: :primary` and default `plan_ir_strict: true`
(`SizeProfile`, `Ide.PebbleToolchain.Elmc`). Apps that hit gaps need either
toolchain extension or temporary `plan_ir_strict: false` in compile opts (not
recommended for shipping).
