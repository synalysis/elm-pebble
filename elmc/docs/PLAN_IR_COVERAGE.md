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
`plan_primary_fallback` diagnostics.

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
| Dotted var `model.field` | Split → `field_access` (1 hop) | Same as C `VarCompile`; not `a.b.c` |
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
9. `compile_linear_branches` — fallback (incomplete)

**Not yet covered** (examples from other apps / future work):

| Pattern | Example | Likely next work |
|---------|---------|------------------|
| Heavy nested `let_in` + list callbacks | large game `update` | Extend `let_in` + closure plan paths |
| `List.map` with record update in lambda | many games | `list_map` + `record_update` in closure body |
| Deep field path `a.b.c` | uncommon in IR today | Chain `field_access` in var lowering |

## Runtime builtins gap

Plan only lowers calls present in `Elmc.Backend.Plan.RuntimeBuiltins`. Missing
ids → `Call.compile_call` → `:unsupported` under strict.

High-value stdlib still often missing (check `runtime_builtins.ex` vs C matrix):

- More `String.*` (`contains`, `slice`, `trim`, …)
- `List.sortBy`, `List.sortWith` (plan builtins)
- `List.sort`, `List.partition`, `List.member`
- `Result.*` / `Task.*` (if reachable on watch)
- Partial application edges for native scalar returns

Add builtins + `expr.ex` / `Call` lowering + conformance test; do not special-case
a template function name.

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
- Legacy C codegen remains the backstop when `plan_ir_strict: false`.

IDE production builds use `plan_ir_mode: :primary` and default `plan_ir_strict: true`
(`SizeProfile`, `Ide.PebbleToolchain.Elmc`). Apps that hit gaps need either
toolchain extension or temporary `plan_ir_strict: false` in compile opts (not
recommended for shipping).
