/**
 * JS host for elmc WASM modules.
 */

import { RC_SUCCESS, createRcRuntime } from "./rc_runtime.js";

export function buildRuntimeImports({ manifestImports = [], immortalStrings = {} }) {
  const runtimeApi = createRcRuntime({ immortalStrings });

  const imports = {
    retain: runtimeApi.buildImport("retain"),
    release: runtimeApi.buildImport("release"),
    release_array_lifo: runtimeApi.buildImport("release_array_lifo"),
  };

  for (const full of manifestImports) {
    const key = full.replace(/^runtime\./, "");
    imports[key] = runtimeApi.buildImport(key);
  }

  return { runtime: imports, helpers: runtimeApi };
}

function invokeClosureExport(instance, manifestClosures, fnIndex, captures, callArgs) {
  const entry = manifestClosures[fnIndex];
  if (!entry) {
    return { rc: RC_SUCCESS, value: 0 };
  }

  const exportFn = instance.exports[entry.export];
  if (typeof exportFn !== "function") {
    return { rc: RC_SUCCESS, value: 0 };
  }

  const args = [...captures, ...callArgs];
  const result = exportFn(...args);

  if (Array.isArray(result)) {
    return { rc: result[0] | 0, value: result[1] | 0 };
  }

  return { rc: RC_SUCCESS, value: result | 0 };
}

export async function loadElmcWasm({
  wasmBytes,
  manifestImports = [],
  manifestClosures = [],
  immortalStrings = {},
}) {
  if (!wasmBytes) {
    throw new Error("loadElmcWasm requires wasmBytes");
  }

  const { runtime, helpers } = buildRuntimeImports({ manifestImports, immortalStrings });
  const { instance } = await WebAssembly.instantiate(wasmBytes, { runtime });

  helpers.setMemory(instance.exports.memory);
  helpers.setClosureInvoker((fnIndex, captures, callArgs) =>
    invokeClosureExport(instance, manifestClosures, fnIndex, captures, callArgs)
  );

  return {
    instance,
    memory: instance.exports.memory,
    helpers,
    callExport(name, args = []) {
      const fn = instance.exports[name];
      if (typeof fn !== "function") {
        throw new Error(`export not found: ${name}`);
      }
      const result = fn(...args);
      if (Array.isArray(result)) {
        return { rc: result[0], value: result[1] };
      }
      return { rc: result, value: 0 };
    },
  };
}

export { RC_SUCCESS };
