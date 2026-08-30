import { readFileSync } from "node:fs";
import { parseHTML } from "linkedom";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";

const [buildDir] = process.argv.slice(2);
if (!buildDir) {
  console.error("usage: wasm_doc_events_probe_runner.mjs <buildDir>");
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

await new Promise((r) => setTimeout(r, 20));

const before = document.getElementById("app")?.textContent ?? "";
if (before !== "wait") {
  console.error(`expected no document event on subscribe, got ${JSON.stringify(before)}`);
  process.exit(1);
}

document.dispatchEvent(new window.Event("click"));
await new Promise((r) => setTimeout(r, 20));

const afterClick = document.getElementById("app")?.textContent ?? "";
if (afterClick !== "click") {
  console.error(`expected Decode.succeed Clicked on document click, got ${JSON.stringify(afterClick)}`);
  process.exit(1);
}

const keyEvent =
  typeof window.KeyboardEvent === "function"
    ? new window.KeyboardEvent("keydown", { key: "a" })
    : Object.assign(new window.Event("keydown"), { key: "a" });
document.dispatchEvent(keyEvent);
await new Promise((r) => setTimeout(r, 20));

const innerText = document.getElementById("app")?.textContent ?? "";
if (innerText !== "ok") {
  console.error(
    `expected Decode.field "key" on keydown, got ${JSON.stringify(innerText)}`
  );
  process.exit(1);
}

helpers.buildImport("release")(programHandle);
if (boot.value) helpers.buildImport("release")(boot.value);
if (boot.initValue) helpers.buildImport("release")(boot.initValue);
if (boot.modelPtr) helpers.buildImport("release")(boot.modelPtr);

console.log("rc_ok doc_events_ok");
