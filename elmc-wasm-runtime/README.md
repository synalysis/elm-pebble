# elmc-wasm-runtime

WASM RC runtime and JS host for elmc web targets.

## Layout

- `runtime/` — C runtime sources (generated/pruned by `elmc compile --target wasm`)
- `host/loader.js` — instantiate app modules with `runtime.*` imports
- `host/rc_runtime.js` — minimal JS RC heap for Phase 1 execution harness tests

## Build

Wasm-only compiles now emit a pruned `runtime/elmc_runtime.c` next to `wasm/elmc_generated.wat`
(see manifest `imports` + `import_signatures`).

To compile the C runtime to wasm32 (requires clang wasm32 target):

```bash
make -C elmc-wasm-runtime runtime
```

## Host usage

```javascript
import { loadElmcWasm } from "./host/loader.js";

const bytes = await fetch("/wasm/app.wasm").then((r) => r.arrayBuffer());
const { helpers, callExport } = await loadElmcWasm({
  wasmBytes: bytes,
  manifestImports: ["runtime.list_append", "runtime.new_int"],
});

const { rc, value } = callExport("elmc_fn_RcTrackListProbe_probeAppend", []);
```

Generated app modules import symbols from the `runtime` module namespace
(`runtime.list_append`, etc.) as declared in `elmc_wasm.manifest.json`.
