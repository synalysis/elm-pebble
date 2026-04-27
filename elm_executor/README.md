# elm_executor

`elm_executor` is the semantic execution engine for the Elm Pebble toolchain.
It evaluates normalized Elm program information for debugger, replay, and
runtime-inspection workflows. It is not an Elm-to-Elixir compiler.

## Goals

- Execute Elm runtime semantics deterministically enough for debugger workflows.
- Provide a generic worker runtime for non-IDE embedding.
- Expose a debugger execution contract consumable by the Elm Pebble IDE.

## CLI

```bash
mix escript.build
./elm_executor check <project_dir>
./elm_executor compile <project_dir> --out-dir <dir>
./elm_executor compile <project_dir> --out-dir <dir> --mode ide_runtime
```

## Runtime Contract

Generated runtime modules expose `debugger_execute/1` and embed the contract:

- `contract`: `elm_executor.runtime_executor.v1`
- `engine`: `elm_executor_runtime_v1`
- deterministic runtime metadata for debugger fingerprints.

## IDE Integration

The IDE adapter is `Ide.Debugger.RuntimeExecutor.ElmExecutorAdapter`.
Configure via:

```elixir
config :ide, Ide.Debugger.RuntimeExecutor,
  external_executor_module: Ide.Debugger.RuntimeExecutor.ElmExecutorAdapter
```
