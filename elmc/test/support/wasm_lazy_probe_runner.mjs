import { readFileSync } from "node:fs";
import { parseHTML } from "linkedom";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";

const [buildDir] = process.argv.slice(2);
if (!buildDir) {
  console.error("usage: wasm_lazy_probe_runner.mjs <buildDir>");
  process.exit(2);
}

const { document, window } = parseHTML(
  "<!doctype html><html><body><div id='app'></div></body></html>"
);
globalThis.document = document;
globalThis.window = window;
globalThis.Node = window.Node;

const logs = [];
const origLog = console.log;
console.log = (...args) => {
  logs.push(args.map((a) => String(a)).join(" "));
  origLog(...args);
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

const countLogs = (prefix) =>
  logs.filter((line) => line.startsWith(`${prefix}: `)).length;

const out = () => document.getElementById("out")?.textContent ?? "";

const click = (id) => {
  const el = document.getElementById(id);
  if (!el) {
    console.error(`missing #${id} html=${document.body?.innerHTML ?? ""}`);
    process.exit(1);
  }
  if (typeof el.click === "function") el.click();
  else el.dispatchEvent(new window.Event("click", { bubbles: true }));
};

// Official VirtualDom thunk: skip when refs match, rerun when they differ.
// `lazy viewCount n` must not run again when only `dummy` changes.
if (out() !== "0" || countLogs("lazy") !== 1 || countLogs("lazy2") !== 2) {
  console.error(
    `expected lazy skip and lazy2 rerun after Noop, got out=${JSON.stringify(out())} logs=${JSON.stringify(logs)} html=${document.getElementById("app")?.innerHTML ?? ""}`
  );
  process.exit(1);
}

click("tick");
await new Promise((r) => setTimeout(r, 20));

if (out() !== "1" || countLogs("lazy") !== 2 || countLogs("lazy2") !== 3) {
  console.error(
    `expected both thunks after one Tick, got out=${JSON.stringify(out())} logs=${JSON.stringify(logs)}`
  );
  process.exit(1);
}

helpers.buildImport("release")(programHandle);
if (boot.value) helpers.buildImport("release")(boot.value);
if (boot.initValue) helpers.buildImport("release")(boot.initValue);
if (boot.modelPtr) helpers.buildImport("release")(boot.modelPtr);

console.log("rc_ok lazy_ok");
