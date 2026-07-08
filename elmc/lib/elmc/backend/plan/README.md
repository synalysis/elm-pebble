# ElmcPlan IR — cross-target contract

`%Elmc.Backend.Plan.Types.FunctionPlan{}` is the target-neutral lowering between
Elm IR and backends:

| Backend | Module | Output |
|---------|--------|--------|
| Pebble C | `Elmc.Backend.C.Lower.Function` | `elmc_generated.c` RC functions |
| Bytecode | `Elmc.Backend.Bytecode.Lower` | `.elmcbc` sections |
| WASM (future) | `Elmc.Backend.Wasm.Lower` | `.wasm` modules |

## Runtime builtin registry

Plan `call_runtime` ops use **logical ids** (`:list_append`, `:cmd2`, …) from
`Elmc.Backend.Plan.RuntimeBuiltins`.

- **C:** `RuntimeBuiltins.c_symbol/1` → `elmc_*` C functions
- **Bytecode:** opcode index in `Bytecode.Opcodes`
- **WASM (future):** `Wasm.RuntimeImports.import_name/1` → `runtime.list_append` etc.

## Platform extensions

Pebble-specific lowering (`pebble_cmd`, `render_cmd`, `pebble_sub`, companion send)
lives in `Plan.Lower.Platform.Pebble`. Web Elm would use `Plan.Lower.Platform.Web`
for `Html` / `Browser` cmds — not in core plan opcodes.

  ## Ownership verification

  `Elmc.Backend.Plan.Verify` runs before any backend. Invariants:

  - No read after `consumes`
  - Single `fn_out` publish per success path
  - Fallible ops inside catch regions when not `rc_required` (per-instr catch) or covered by frame catch when `rc_required`
  - No leaked owned registers at block `ret` (`EpilogueRelease` inserts plan `:release` ops; C/bytecode backends defer to epilogue LIFO)

## Feature flag

`opts[:plan_ir_mode]` — `:off` | `:shadow` | `:primary`

- `:shadow` — build + verify plan alongside legacy C (tests may set `plan_ir_raise: true`)
- `:primary` — emit C from plan via `C.Lower.Function`; legacy C fusion is skipped when plan lowering succeeds. Functions plan cannot lower yet fall back to legacy codegen and emit a `plan_primary_fallback` compile warning (error when `plan_ir_strict: true` on reachable functions). Successful primary compiles also emit an info diagnostic (`plan_primary_coverage`) with reachable/Main stats; reachable gaps emit `plan_primary_gap` (warning, or error when strict).

`Elmc.Backend.Plan.Defaults` sets `default_plan_ir_mode` to `:primary` (override with `Application.put_env(:elmc, :default_plan_ir_mode, :off)`). `Elmc.compile/2` and `Elmc.CLI` apply these defaults; the test suite sets `:off` in `test/test_helper.exs` so legacy C codegen tests stay stable.

`direct_plan_call_abi?` — plan-primary functions that are not partial-application
wrappers emit and call with named parameters instead of `args`/`argc`.

`plan_ir_strict` defaults to `true` in `:primary` mode. Set `plan_ir_strict: false` to allow legacy fallback warnings while migrating a construct.

Explicit `plan_ir_mode: :off` emits an info diagnostic (`plan_legacy_codegen`). The test suite sets `default_plan_ir_mode` to `:off` without the marker so legacy tests stay quiet.

Tagged `case` lowering uses a **multi-block CFG**: entry `switch_tag` dispatch
(per-arm block ids are assigned after arm bodies are lowered so nested cases
cannot steal sibling arm slots), per-arm blocks ending in `br`, and a merge
block with `switch_ctor_tag`.

## Bytecode

`Bytecode.Lower` encodes verified plans to `.elmcbc` sections (v3 wire format:
fn table + block IP table + code + embedded lambda sections); `Bytecode.ProjectWriter` emits
`bytecode/elmc_bytecode.manifest.json` plus per-function `.elmcbc` files when
`plan_ir_mode` is `:shadow` or `:primary`. The manifest includes `plan_coverage`
(`all`, `Main`, and `reachable` lowering stats), `pruned_count` for dead bundled
helpers omitted from `.elmcbc` emission, and a per-function index. `Bytecode.Artifacts.read_summary/1` and
`Bytecode.Loader` reload manifest entries for interpreter smoke tests. IDE dev compiles
default to `plan_ir_mode: :primary` (dev and Pebble PBW / `prod: true` builds) and attach
`elmc_bytecode_manifest` on compile results. The IDE debugger shows a **Plan bytecode**
panel (function list + smoke **Run** buttons) and MCP `debugger.bytecode` supports
`summary` / `functions` / `run`. `Ide.Debugger.BytecodeRunner` reloads manifest entries; `Bytecode.Runtime` interprets sections with structured `render_cmd` / `pebble_sub` /
`pebble_cmd` values; `Bytecode.Program` links transitive
`call_fn` callees and dispatches nested plans via the interpreter `plans` map.
Opcode table lives in `Bytecode.Opcodes` (includes `int_arith`, `render_cmd`,
`pebble_sub`, `switch_ctor_tag`, `pebble_cmd`, …). `call_fn` targets are
indexed via `Bytecode.FnTable`; optional `fn_registry` stubs remain for isolated
unit tests. Closure dispatch passes `plan_key: {module, name}` so embedded lambda
sections resolve under the parent function's `lambdas` array (manifest v3).
`ManifestProgram.load_linked/2` and `Program.link/3` walk `call_fn` edges in embedded
lambda sections so `list_all` / closure bodies can reach helpers like `offsetFits`.
`Runtime.run_section/2` keeps function parameters in an immutable `params` snapshot;
`load_param` copies from that snapshot into scratch locals so low-numbered dest
registers cannot clobber later param loads (for example `spawnPiece` reloading `board`).

## Record layout

IR `record_literal` fields may arrive in alphabetical order. Plan lowering
canonicalizes field order via `Process.get(:elmc_record_alias_shapes)` (same
shape map as C codegen) before `record_new`. `record_get` / `record_update` use
that map for `field_index` words in bytecode and plan verify.

`Bytecode.ProjectWriter` sets `elmc_record_alias_shapes` from IR when emitting
`.elmcbc` files — C `prepare_emit_session!` resets process state before bytecode
write, so the writer must republish shapes.

## `if` lowering

`if` uses a three-block CFG (`br_if` → per-arm blocks → merge `phi`), not eager
evaluation of both branches. `case` on `Maybe` (`Nothing` + `Just`/var) uses the same
CFG shape so untaken arms do not run. Outer `let` bindings remain visible in arm blocks;
nested `if` reserves block ids to avoid arm/merge collisions.

CFG arms reload params at `call_fn` sites when a cached param slot was loaded in a
different block, so callee args never read stale local slots. Each CFG arm block
starts with a cleared param cache so `load_param` runs again before the arm body.

## Platform op effects

`pebble_cmd` transfers ownership of its parameter values (`borrows` + `consumes`
via `partition_call_args`). `render_cmd` and `pebble_sub` only **borrow**
parameters — the runtime reads coords/ints/strings without taking RC ownership,
so the same scratch register can feed multiple draw ops in one function.

`Just` / bare-var `Maybe` arms use `maybe_just_payload` (not `union_payload`).
The bytecode interpreter implements `maybe_just_payload` / `union_payload` stubs.
Record field expressions lower through `Expr.compile` so kernel `__add__` becomes
`int_arith`, not a missing `call_fn`. List `++` (`__append__`) lowers to
`list_append`, not a missing `Main.__append__`.

`List.foldl` / `filterMap` lambdas that destructure a tuple parameter
(`tupleArg` → `dx`/`dy` → `acc`) are flattened to `(tupleArg, acc)` with
`tuple_proj` prelude ops in the embedded lambda section.

**C primary:** `make_closure` lowers to `elmc_closure_new_rc` and embedded lambda
bodies emit as `static RC …_closure_N` helpers (see `Elmc.Backend.C.Lower.Lambda`).
Nested lambdas recurse through the parent plan's `lambdas` array.

`Pebble.Ui.toUiNode` lowers to `retain` on the render-op list (identity for
bytecode/C plan paths that already emit `render_cmd` values).
