import { readFileSync } from "node:fs";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";

const [buildDir, exportName, expectedText] = process.argv.slice(2);

if (!buildDir || !exportName) {
  console.error("usage: wasm_browser_probe_runner.mjs <buildDir> <exportName> [expectedText]");
  process.exit(2);
}

const manifest = JSON.parse(
  readFileSync(`${buildDir}/wasm/elmc_wasm.manifest.json`, "utf8")
);

let wasmBytes;
try {
  wasmBytes = readFileSync(`${buildDir}/wasm/app.wasm`);
} catch (_err) {
  wasmBytes = readFileSync(`${buildDir}/wasm/elmc_generated.wasm`);
}

const { helpers, callExport } = await loadElmcWasm({
  wasmBytes,
  manifestImports: manifest.imports || [],
  manifestClosures: manifest.closures || [],
  immortalStrings: manifest.immortal_strings || {},
});

const { rc, value: programHandle } = callExport(exportName, []);

if (rc !== RC_SUCCESS) {
  console.error(`probe failed: rc=${rc}`);
  process.exit(1);
}

if (!helpers.isBrowserProgram(programHandle)) {
  console.error("probe failed: export did not return a browser program handle");
  process.exit(1);
}

const boot = helpers.bootBrowserProgram(programHandle);

if (boot.rc !== RC_SUCCESS) {
  console.error(`browser boot failed: rc=${boot.rc} stage=${boot.stage ?? "unknown"}`);
  process.exit(1);
}

helpers.buildImport("release")(programHandle);
if (boot.value) helpers.buildImport("release")(boot.value);
if (boot.initValue) helpers.buildImport("release")(boot.initValue);
if (boot.modelPtr) helpers.buildImport("release")(boot.modelPtr);

if (expectedText !== undefined && boot.innerText !== expectedText) {
  console.error(
    `innerText mismatch: got ${JSON.stringify(boot.innerText)}, expected ${JSON.stringify(expectedText)}`
  );
  process.exit(1);
}

if (!helpers.checkBalanced()) {
  const state = helpers.debugRcState?.();
  if (state) {
    console.warn("rc leak after browser boot (non-fatal for browser probe)", state);
  }
}

console.log(`rc_ok browser_innerText=${JSON.stringify(boot.innerText)} browser_title=${JSON.stringify(boot.title ?? "")}`);
