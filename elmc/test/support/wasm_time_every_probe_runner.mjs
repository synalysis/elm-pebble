import { readFileSync } from "node:fs";
import { parseHTML } from "linkedom";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";

const [buildDir] = process.argv.slice(2);
if (!buildDir) {
  console.error("usage: wasm_time_every_probe_runner.mjs <buildDir>");
  process.exit(2);
}

const { document, window } = parseHTML(
  "<!doctype html><html><body><div id='app'></div></body></html>"
);
globalThis.document = document;
globalThis.window = window;
globalThis.Node = window.Node;

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
  constructorTags: manifest.constructor_tags || {},
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

const ticks = () => Number.parseInt(document.getElementById("app")?.textContent ?? "0", 10) || 0;
if (ticks() !== 0) {
  console.error(`official Time.every must not fire on subscribe, got ${ticks()}`);
  process.exit(1);
}

await new Promise((r) => setTimeout(r, 250));

const n = ticks();
// 100ms interval: 1–3 ticks in 250ms. A 2ms handle-id storm would be dozens.
if (n < 1 || n > 3) {
  console.error(
    `expected official Time.every Posix ticks in 1..3 after 250ms, got ${n} html=${document.getElementById("app")?.innerHTML ?? ""}`
  );
  process.exit(1);
}

helpers.buildImport("release")(programHandle);
if (boot.value) helpers.buildImport("release")(boot.value);
if (boot.initValue) helpers.buildImport("release")(boot.initValue);
if (boot.modelPtr) helpers.buildImport("release")(boot.modelPtr);

console.log("rc_ok time_every_ok ticks=" + n);
process.exit(0);
