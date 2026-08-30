import { readFileSync } from "node:fs";
import { parseHTML } from "linkedom";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";

const [buildDir, expectedText] = process.argv.slice(2);
if (!buildDir) {
  console.error("usage: wasm_viewport_probe_runner.mjs <buildDir> [expectedText]");
  process.exit(2);
}

const { document } = parseHTML(
  "<!doctype html><html><body><div id='app'></div><div id='box'></div></body></html>"
);
const window = document.defaultView;
globalThis.document = document;
globalThis.window = window;
globalThis.Node = window.Node;

Object.defineProperty(window, "innerWidth", { configurable: true, get: () => 111 });
Object.defineProperty(window, "innerHeight", { configurable: true, get: () => 222 });
Object.defineProperty(window, "pageXOffset", { configurable: true, get: () => 3 });
Object.defineProperty(window, "pageYOffset", { configurable: true, get: () => 4 });

for (const node of [document.body, document.documentElement]) {
  Object.defineProperty(node, "scrollWidth", { configurable: true, get: () => 555 });
  Object.defineProperty(node, "scrollHeight", { configurable: true, get: () => 666 });
}

const box = document.getElementById("box");
Object.defineProperty(box, "scrollWidth", { configurable: true, get: () => 80 });
Object.defineProperty(box, "scrollHeight", { configurable: true, get: () => 90 });
Object.defineProperty(box, "scrollLeft", { configurable: true, get: () => 5 });
Object.defineProperty(box, "scrollTop", { configurable: true, get: () => 6 });
Object.defineProperty(box, "clientWidth", { configurable: true, get: () => 70 });
Object.defineProperty(box, "clientHeight", { configurable: true, get: () => 75 });
box.getBoundingClientRect = () => ({ left: 10, top: 20, width: 30, height: 40 });

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

await new Promise((r) => setTimeout(r, 80));

const innerText = document.getElementById("app")?.textContent ?? boot.innerText ?? "";
const expected = expectedText || "555x666@3,4:111x222>80x90@5,6:70x75|13,24:30x40";
if (innerText !== expected) {
  console.error(
    `viewport field-order mismatch: got ${JSON.stringify(innerText)}, expected ${JSON.stringify(expected)}`
  );
  process.exit(1);
}

helpers.buildImport("release")(programHandle);
if (boot.value) helpers.buildImport("release")(boot.value);
if (boot.initValue) helpers.buildImport("release")(boot.initValue);
if (boot.modelPtr) helpers.buildImport("release")(boot.modelPtr);

console.log(`rc_ok viewport=${innerText}`);
