import { readFileSync } from "node:fs";
import { loadElmcWasm } from "../../../elmc-wasm-runtime/host/loader.js";

export function readWasmManifest(buildDir) {
  return JSON.parse(readFileSync(`${buildDir}/wasm/elmc_wasm.manifest.json`, "utf8"));
}

export function readWasmBytes(buildDir) {
  return readFileSync(`${buildDir}/wasm/app.wasm`);
}

export function loadWasmFromBuildDir(buildDir, extra = {}) {
  const manifest = readWasmManifest(buildDir);
  return loadElmcWasm({
    wasmBytes: readWasmBytes(buildDir),
    manifestImports: manifest.imports || [],
    manifestClosures: manifest.closures || [],
    closureCount: manifest.closure_count ?? null,
    immortalStrings: manifest.immortal_strings || {},
    constructorTags: manifest.constructor_tags || {},
    ...extra,
  });
}
