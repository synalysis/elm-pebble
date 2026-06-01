# Debugger compile contract

Debugger metadata (subscriptions, cmd outlines, msg constructors, etc.) must come from
**compile-time artifacts**, not ad-hoc AST walks during hot reload.

## Storage

| Shell key | Role |
|-----------|------|
| `debugger_contract` | Decoded `debugger_contract.v1` map (preferred) |
| `debugger_contract_b64` | Term-encoded artifact from `Ide.Compiler` |
| `elm_introspect` | Legacy key (migrated to `debugger_contract` on read; do not write) |

Core IR (`elm_executor_core_ir_b64`) remains the source of truth for **execution**
(init / update / view). The debugger contract is the source of truth for **declared
effects** until those fields live on Core IR itself.

## APIs

- **Build:** `Ide.Debugger.CompileContract.build_for_project_dir/1` (compile),
  `CompileContract.analyze_source/2` (tests / editor only)
- **Read:** `Ide.Debugger.RuntimeArtifacts.introspect/1` → `CompileContract.from_shell/1`

## Policy

1. Do **not** call `ElmEx.DebuggerContract.analyze_*` outside `compile_contract.ex`
   (enforced by `mix ide.boundary_check`).
2. Do **not** extend `EffectAnalysis` for new debugger features — extend Core IR /
   compile lowering instead.
3. Hot reload for watch `Main.elm` / phone `CompanionApp.elm` must use `debugger_contract`
   from compile ingest (`SurfaceCompileArtifacts` / `Ide.Compiler`). Other modules may still
   use `CompileContract.analyze_source/2` (editor helpers). Non-entrypoint modules still
   use parse-time analysis until Core IR carries effect metadata.

## Elimination checklist

- [x] Compile attaches `debugger_contract_b64` with Core IR
- [x] Shell writes `debugger_contract` on bootstrap (not `elm_introspect`)
- [x] Move analyzer from `Ide.Debugger.ElmIntrospect` into `elm_ex` (`ElmEx.DebuggerContract`)
- [x] Hot reload entrypoints use compile `debugger_contract` (fallback parse if compile missing)
- [x] `optional_runtime_artifacts` propagates `debugger_contract_*` with Core IR
- [x] Compile contract from `Bridge.load_project` modules (no second parse on full projects)
- [x] Core IR effect overlay for subscriptions/cmd (`EffectsFromCoreIR` + compile merge)
- [x] Snapshots use `debugger_contract` key (`elm_introspect` read fallback only)
- [x] Core IR subscription rows normalized (import targets, Msg tag → constructor)
- [x] Tests use `debugger_contract` shell key; legacy `elm_introspect` in model migrates to shell
- [x] Remove `Ide.Debugger.ElmIntrospect` facade module (tests use `CompileContract` / `ContractTestSupport`)
- [x] `CompileContract.from_shell/1` migrates legacy `elm_introspect` via `RuntimeArtifacts.normalize_contract_shell/1` (no separate read path)
- [x] Template corpus subscription-step gate covers all project templates (Core IR update + contract payloads)
- [x] Timeline event `debugger.contract` (legacy `debugger.elm_introspect` still recognized on read)
- [x] `DebuggerContractSnapshot` replaces `ElmIntrospectSnapshot` (delegate module removed)
- [x] UI helpers `debugger_contract_at_cursor` / `format_debugger_contract_brief` (legacy names retained)
- [x] Runtime host callback `maybe_append_contract` (was `maybe_append_elm_introspect`)
- [x] Tests renamed to `DebuggerContract*` modules
- [x] Executor eval context uses `debugger_contract` key (`EvalContext`; `elm_introspect` read/write alias)
- [x] MCP `cursor_inspect` prefers `debugger_contract` (`elm_introspect` duplicate retained)
