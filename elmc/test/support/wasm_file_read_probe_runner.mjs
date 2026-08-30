import { readFileSync } from "node:fs";
import { parseHTML } from "linkedom";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";

const [buildDir] = process.argv.slice(2);
if (!buildDir) {
  console.error("usage: wasm_file_read_probe_runner.mjs <buildDir>");
  process.exit(2);
}

if (typeof File === "undefined") {
  console.error("File constructor is not available");
  process.exit(2);
}

const { document, window } = parseHTML(
  "<!doctype html><html><body><div id='app'></div></body></html>"
);
globalThis.document = document;
globalThis.window = window;
globalThis.Node = window.Node;

let pendingFiles = [];
const origCreateElement = document.createElement.bind(document);
document.createElement = function createElement(tag, ...rest) {
  const el = origCreateElement(tag, ...rest);
  if (String(tag).toLowerCase() === "input") {
    const origClick = typeof el.click === "function" ? el.click.bind(el) : () => {};
    el.click = function click() {
      if (pendingFiles.length) {
        Object.defineProperty(el, "files", {
          configurable: true,
          value: pendingFiles,
        });
        el.dispatchEvent(new window.Event("change", { bubbles: true }));
      }
      return origClick();
    };
  }
  return el;
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

pendingFiles = [new File(["hello"], "notes.md", { type: "text/plain" })];
click("pick");

let text = out();
for (
  let i = 0;
  i < 25 &&
  (!text.includes("hello") || !text.includes("data:") || !text.endsWith("|104"));
  i++
) {
  await new Promise((r) => setTimeout(r, 20));
  text = out();
}

const parts = text.split("|");
const name = parts[0];
const body = parts[1];
const firstByte = parts[parts.length - 1];
const url = parts.slice(2, -1).join("|");
if (
  name !== "notes.md" ||
  body !== "hello" ||
  !String(url).startsWith("data:") ||
  firstByte !== "104"
) {
  console.error(
    `expected File.toString/toUrl/toBytes after Select, got ${JSON.stringify(text)}`
  );
  process.exit(1);
}

if (!url.includes("text/plain") && !url.includes("aGVsbG8")) {
  console.error(`expected data URL for hello / text/plain, got ${JSON.stringify(url)}`);
  process.exit(1);
}

helpers.buildImport("release")(programHandle);
if (boot.value) helpers.buildImport("release")(boot.value);
if (boot.initValue) helpers.buildImport("release")(boot.initValue);
if (boot.modelPtr) helpers.buildImport("release")(boot.modelPtr);

console.log("rc_ok file_read_ok");
