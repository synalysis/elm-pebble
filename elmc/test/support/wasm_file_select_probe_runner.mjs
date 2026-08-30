import { readFileSync } from "node:fs";
import { parseHTML } from "linkedom";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";

const [buildDir] = process.argv.slice(2);
if (!buildDir) {
  console.error("usage: wasm_file_select_probe_runner.mjs <buildDir>");
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
const pickers = [];
const downloads = [];

const origCreateElement = document.createElement.bind(document);
document.createElement = function createElement(tag, ...rest) {
  const el = origCreateElement(tag, ...rest);
  const name = String(tag).toLowerCase();
  if (name === "input") {
    const origClick = typeof el.click === "function" ? el.click.bind(el) : () => {};
    el.click = function click() {
      pickers.push({
        accept: String(el.accept || ""),
        multiple: Boolean(el.multiple),
      });
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
  if (name === "a") {
    const origClick = typeof el.click === "function" ? el.click.bind(el) : () => {};
    el.click = function click() {
      downloads.push({
        href: String(el.href || ""),
        download: String(el.download || ""),
      });
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

pendingFiles = [new File(["hi"], "notes.md", { type: "text/plain" })];
click("pick");
await new Promise((r) => setTimeout(r, 20));

if (out() !== "notes.md") {
  console.error(`expected File.Select.file to deliver notes.md, got ${JSON.stringify(out())}`);
  process.exit(1);
}

const lastPick = pickers[pickers.length - 1];
if (!lastPick || lastPick.multiple || lastPick.accept !== "text/plain") {
  console.error(`expected single text/plain picker, got ${JSON.stringify(pickers)}`);
  process.exit(1);
}

pendingFiles = [
  new File(["a"], "a.txt", { type: "text/plain" }),
  new File(["b"], "b.txt", { type: "text/plain" }),
];
click("picks");
await new Promise((r) => setTimeout(r, 20));

if (out() !== "a.txt:b.txt") {
  console.error(
    `expected File.Select.files first+rest names, got ${JSON.stringify(out())}`
  );
  process.exit(1);
}

const lastPicks = pickers[pickers.length - 1];
if (!lastPicks?.multiple || lastPicks.accept !== "text/plain") {
  console.error(`expected multiple text/plain picker, got ${JSON.stringify(pickers)}`);
  process.exit(1);
}

const beforeCancel = out();
pendingFiles = [];
click("pick");
await new Promise((r) => setTimeout(r, 20));
if (out() !== beforeCancel) {
  console.error(
    `expected official empty picker to stay silent, got ${JSON.stringify(out())}`
  );
  process.exit(1);
}

click("url");
await new Promise((r) => setTimeout(r, 20));

const urlClick = downloads[downloads.length - 1];
if (
  !urlClick ||
  !urlClick.href.includes("example.com/a.png") ||
  urlClick.download !== ""
) {
  console.error(
    `expected File.Download.url <a href download="">, got ${JSON.stringify(downloads)}`
  );
  process.exit(1);
}

helpers.buildImport("release")(programHandle);
if (boot.value) helpers.buildImport("release")(boot.value);
if (boot.initValue) helpers.buildImport("release")(boot.initValue);
if (boot.modelPtr) helpers.buildImport("release")(boot.modelPtr);

console.log("rc_ok file_select_ok");
