# Elmc

`elmc` is an experimental Elm-to-C compiler scaffold that targets:

- `elm/core`-centric projects
- reference counting runtime semantics
- Ports integration through a C callback ABI

## CLI

```bash
mix escript.build
./elmc check /path/to/elm-project
./elmc compile /path/to/elm-project --out-dir build
./elmc compile /path/to/elm-project --out-dir build --target wasm
./elmc compile /path/to/elm-project --out-dir build --target c,wasm
./elmc compile /path/to/elm-project --out-dir build --no-strip-dead-code
./elmc manifest /path/to/elm-project
```

WASM output (with `--target wasm` or `--target c,wasm` and `plan_ir_mode` `:shadow`/`:primary`):

- `build/wasm/elmc_generated.wat` — linked WASM text module
- `build/wasm/elmc_wasm.manifest.json` — function table, imports, coverage

Optional CI tool: [wabt](https://github.com/WebAssembly/wabt) (`wat2wasm`, `wasm-validate`).

Runtime package: [`elmc-wasm-runtime/`](../elmc-wasm-runtime/) (C RC runtime + JS host).

By default, `compile` strips dead (unreachable) functions from generated C using entry-module reachability (`init`, `update`, `view`, `subscriptions`, `main` roots).

## Current Output Layout

- `build/runtime/elmc_runtime.{h,c}`: RC runtime
- `build/ports/elmc_ports.h`: Ports callback ABI
- `build/c/elmc_generated.{h,c}`: generated C stubs from lowered IR
- `build/c/elmc_worker.{h,c}`: worker loop adapter (`init`/`update`) for host integration
- `build/c/elmc_pebble.{h,c}`: Pebble-facing shim (`init`/`tick`/`dispatch`/`view`) over worker adapter
- `build/CMakeLists.txt`: build entrypoint

