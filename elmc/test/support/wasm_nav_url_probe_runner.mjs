import { readFileSync } from "node:fs";
import { parseHTML } from "linkedom";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";

const [buildDir, kind, expectedUrl] = process.argv.slice(2);
if (!buildDir || (kind !== "push" && kind !== "replace") || !expectedUrl) {
  console.error("usage: wasm_nav_url_probe_runner.mjs <buildDir> <push|replace> <url>");
  process.exit(2);
}

const { document, window } = parseHTML(
  "<!doctype html><html><body><div id='app'></div></body></html>"
);
globalThis.document = document;
globalThis.window = window;
globalThis.Node = window.Node;

const pushes = [];
const replaces = [];
window.history = window.history || {};
window.history.pushState = (_state, _title, url) => {
  pushes.push(String(url ?? ""));
};
window.history.replaceState = (_state, _title, url) => {
  replaces.push(String(url ?? ""));
};

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

await new Promise((r) => setTimeout(r, 20));

const hits = kind === "push" ? pushes : replaces;
const other = kind === "push" ? replaces : pushes;
if (hits.length !== 1 || !hits[0].includes(expectedUrl) || other.length !== 0) {
  console.error(
    `expected Navigation ${kind}Url ${expectedUrl}, got push=${JSON.stringify(pushes)} replace=${JSON.stringify(replaces)}`
  );
  process.exit(1);
}

helpers.buildImport("release")(programHandle);
if (boot.value) helpers.buildImport("release")(boot.value);
if (boot.initValue) helpers.buildImport("release")(boot.initValue);
if (boot.modelPtr) helpers.buildImport("release")(boot.modelPtr);

console.log("rc_ok nav_url_ok");
