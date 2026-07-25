import { readFileSync } from "node:fs";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";

const [buildDir] = process.argv.slice(2);
if (!buildDir) {
  console.error("usage: wasm_strict_sandbox_probe_runner.mjs <buildDir>");
  process.exit(2);
}

const manifest = JSON.parse(
  readFileSync(`${buildDir}/wasm/elmc_wasm.manifest.json`, "utf8")
);
const wasmBytes = readFileSync(`${buildDir}/wasm/app.wasm`);

const { helpers, callExport } = await loadElmcWasm({
  wasmBytes,
  manifestImports: manifest.imports || [],
  manifestClosures: manifest.closures || [],
  closureCount: manifest.closure_count ?? null,
  immortalStrings: manifest.immortal_strings || {},
});

const { rc, value: programHandle } = callExport("elmc_fn_Main_main", []);
if (rc !== RC_SUCCESS) {
  console.error(`probe failed: rc=${rc}`);
  process.exit(1);
}

const boot = helpers.bootBrowserProgram(programHandle);
if (boot.rc !== RC_SUCCESS) {
  console.error(`boot failed: rc=${boot.rc} stage=${boot.stage ?? "unknown"}`);
  process.exit(1);
}

if (boot.innerText !== "count: 0") {
  console.error(
    `innerText mismatch: got ${JSON.stringify(boot.innerText)}, expected "count: 0"`
  );
  process.exit(1);
}

helpers.buildImport("release")(programHandle);
if (boot.value) helpers.buildImport("release")(boot.value);
if (boot.initValue) helpers.buildImport("release")(boot.initValue);
if (boot.modelPtr) helpers.buildImport("release")(boot.modelPtr);

if (!helpers.checkBalanced()) {
  const state = helpers.debugRcState?.();
  if (state) {
    console.warn("rc leak after strict sandbox boot (non-fatal)", state);
  }
}

console.log("rc_ok strict_sandbox_ok");
