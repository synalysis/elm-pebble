import { readFileSync } from "node:fs";
import { parseHTML } from "linkedom";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";

const [buildDir] = process.argv.slice(2);
if (!buildDir) {
  console.error("usage: wasm_html_handler_probe_runner.mjs <buildDir>");
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

const out = () => document.getElementById("out")?.textContent ?? "";

const click = (id) => {
  const el = document.getElementById(id);
  if (!el) {
    console.error(`missing #${id} html=${document.body?.innerHTML ?? ""}`);
    process.exit(1);
  }
  const ev = new window.Event("click", { bubbles: true, cancelable: true });
  let prevented = false;
  let stopped = false;
  ev.preventDefault = () => {
    prevented = true;
    ev.defaultPrevented = true;
  };
  ev.stopPropagation = () => {
    stopped = true;
  };
  el.dispatchEvent(ev);
  return { prevented, stopped };
};

const prevent = click("prevent");
await new Promise((r) => setTimeout(r, 20));
if (!prevent.prevented || prevent.stopped || out() !== "P") {
  console.error(
    `expected preventDefaultOn click, got prevented=${prevent.prevented} stopped=${prevent.stopped} out=${JSON.stringify(out())} html=${document.getElementById("app")?.innerHTML ?? ""}`
  );
  process.exit(1);
}

const stop = click("stop");
await new Promise((r) => setTimeout(r, 20));
if (stop.prevented || !stop.stopped || out() !== "PS") {
  console.error(
    `expected stopPropagationOn click, got prevented=${stop.prevented} stopped=${stop.stopped} out=${JSON.stringify(out())}`
  );
  process.exit(1);
}

const custom = click("custom");
await new Promise((r) => setTimeout(r, 20));
if (!custom.prevented || !custom.stopped || out() !== "PSC") {
  console.error(
    `expected Html.Events.custom flags, got prevented=${custom.prevented} stopped=${custom.stopped} out=${JSON.stringify(out())}`
  );
  process.exit(1);
}

helpers.buildImport("release")(programHandle);
if (boot.value) helpers.buildImport("release")(boot.value);
if (boot.initValue) helpers.buildImport("release")(boot.initValue);
if (boot.modelPtr) helpers.buildImport("release")(boot.modelPtr);

console.log("rc_ok html_handler_ok");
