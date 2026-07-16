/**
 * JS host for elmc WASM modules.
 */

import { RC_SUCCESS, createRcRuntime } from "./rc_runtime.js";

export function buildRuntimeImports({ manifestImports = [], immortalStrings = {}, constructorTags = {} }) {
  const runtimeApi = createRcRuntime({ immortalStrings, constructorTags });

  const imports = {
    retain: runtimeApi.buildImport("retain"),
    release: runtimeApi.buildImport("release"),
    release_array_lifo: runtimeApi.buildImport("release_array_lifo"),
  };

  for (const full of manifestImports) {
    const key = String(full).replace(/^runtime\./, "");
    imports[key] = runtimeApi.buildImport(key);
  }

  return { runtime: imports, helpers: runtimeApi };
}

function withCallRoots(helpers, roots, fn) {
  helpers.pushCallRoots(roots);
  try {
    return fn();
  } finally {
    helpers.popCallRoots();
  }
}

function resolveClosureExportName(manifestClosures, fnIndex, closureCount) {
  const entry = Array.isArray(manifestClosures) ? manifestClosures[fnIndex] : null;
  if (typeof entry === "string" && entry) {
    return entry;
  }
  if (entry && typeof entry.export === "string" && entry.export) {
    return entry.export;
  }
  if (typeof closureCount === "number" && fnIndex >= 0 && fnIndex < closureCount) {
    return `c${fnIndex}`;
  }
  return null;
}

function invokeClosureExport(
  instance,
  manifestClosures,
  closureCount,
  fnIndex,
  captures,
  callArgs,
  helpers
) {
  const exportName = resolveClosureExportName(manifestClosures, fnIndex, closureCount);
  if (!exportName) {
    return { rc: RC_SUCCESS, value: 0 };
  }

  const exportFn = instance.exports[exportName];
  if (typeof exportFn !== "function") {
    return { rc: RC_SUCCESS, value: 0 };
  }

  // Plan/WASM param indices: captures first, then call args (matches C closure ABI).
  const args = [...captures, ...callArgs];
  return withCallRoots(helpers, args, () => {
    const result = exportFn(...args);

    if (Array.isArray(result)) {
      return { rc: result[0] | 0, value: result[1] | 0 };
    }

    return { rc: RC_SUCCESS, value: result | 0 };
  });
}

async function compileWasmModule({ wasmBytes, wasmResponse }) {
  if (wasmBytes) {
    return {
      module: await WebAssembly.compile(wasmBytes),
      compile_mode: "buffer",
    };
  }
  if (!wasmResponse) {
    throw new Error("loadElmcWasm requires wasmBytes or wasmResponse");
  }

  const fallback =
    typeof wasmResponse.clone === "function" ? wasmResponse.clone() : wasmResponse;

  if (typeof WebAssembly.compileStreaming === "function") {
    try {
      return {
        module: await WebAssembly.compileStreaming(wasmResponse),
        compile_mode: "streaming",
      };
    } catch {
      // Wrong MIME / non-browser Response — compile from bytes instead.
    }
  }

  const bytes = new Uint8Array(await fallback.arrayBuffer());
  return {
    module: await WebAssembly.compile(bytes),
    compile_mode: "buffer",
  };
}

export async function loadElmcWasm({
  wasmBytes,
  wasmResponse = null,
  manifestImports = null,
  manifestClosures = [],
  closureCount = null,
  immortalStrings = {},
  constructorTags = {},
}) {
  const t0 = performance.now();
  const { module, compile_mode } = await compileWasmModule({ wasmBytes, wasmResponse });
  const compileMs = performance.now() - t0;

  let importsList = manifestImports;
  if (!Array.isArray(importsList) || importsList.length === 0) {
    importsList = WebAssembly.Module.imports(module)
      .filter((entry) => entry.module === "runtime" && entry.kind === "function")
      .map((entry) => `runtime.${entry.name}`);
  }

  const resolvedClosureCount =
    typeof closureCount === "number"
      ? closureCount
      : Array.isArray(manifestClosures)
        ? manifestClosures.length
        : 0;

  const { runtime, helpers } = buildRuntimeImports({
    manifestImports: importsList,
    immortalStrings,
    constructorTags,
  });

  const tInst = performance.now();
  const instantiated = await WebAssembly.instantiate(module, { runtime });
  // instantiate(Module) resolves to Instance; instantiate(bytes) resolves to {instance, module}.
  const instance = instantiated instanceof WebAssembly.Instance ? instantiated : instantiated.instance;
  const instantiateMs = performance.now() - tInst;

  helpers.setMemory(instance.exports.memory);
  helpers.setClosureInvoker((fnIndex, captures, callArgs) =>
    invokeClosureExport(
      instance,
      manifestClosures,
      resolvedClosureCount,
      fnIndex,
      captures,
      callArgs,
      helpers
    )
  );

  return {
    instance,
    memory: instance.exports.memory,
    helpers,
    timing: {
      compile_ms: +compileMs.toFixed(1),
      instantiate_ms: +instantiateMs.toFixed(1),
      compile_mode,
    },
    callExport(name, args = []) {
      const fn = instance.exports[name];
      if (typeof fn !== "function") {
        throw new Error(`export not found: ${name}`);
      }
      return withCallRoots(helpers, args, () => {
        const result = fn(...args);
        if (Array.isArray(result)) {
          return { rc: result[0], value: result[1] };
        }
        return { rc: result, value: 0 };
      });
    },
  };
}

export { RC_SUCCESS };
