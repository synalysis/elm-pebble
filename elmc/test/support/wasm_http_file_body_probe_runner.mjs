import { readFileSync } from "node:fs";
import { parseHTML } from "linkedom";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";

const [buildDir] = process.argv.slice(2);
if (!buildDir) {
  console.error("usage: wasm_http_file_body_probe_runner.mjs <buildDir>");
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

const fileText = async (value) => {
  if (!value) return "";
  if (typeof value.text === "function") return String(await value.text());
  if (typeof value === "string") return value;
  return "";
};

let fileCalls = 0;
let partCalls = 0;
let fileName = "";
let fileMime = "";
let fileBody = "";
let partName = "";
let partMime = "";
let partBody = "";

globalThis.fetch = async (url, init = {}) => {
  const href = String(url);
  const ok = {
    ok: true,
    status: 200,
    statusText: "OK",
    url: href,
    headers: {
      forEach(fn) {
        fn("text/plain", "content-type");
      },
      get: (k) => (k === "content-type" ? "text/plain" : null),
    },
    text: async () => "",
    arrayBuffer: async () => new ArrayBuffer(0),
  };

  if (href.includes("/file")) {
    fileCalls += 1;
    const body = init.body;
    fileName = String(body?.name ?? "");
    fileMime = String(body?.type ?? init.headers?.["Content-Type"] ?? "");
    fileBody = await fileText(body);
    return ok;
  }

  if (href.includes("/part")) {
    partCalls += 1;
    const body = init.body;
    const doc =
      typeof FormData !== "undefined" && body instanceof FormData ? body.get("doc") : null;
    partName = String(doc?.name ?? "");
    partMime = String(doc?.type ?? "");
    partBody = await fileText(doc);
    return ok;
  }

  console.error(`unexpected fetch ${href}`);
  process.exit(1);
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

let innerText = "";
const deadline = Date.now() + 400;
while (Date.now() < deadline) {
  innerText = document.getElementById("out")?.textContent ?? "";
  if (innerText === "ok|ok") break;
  await new Promise((r) => setTimeout(r, 20));
}

if (fileCalls < 1 || partCalls < 1) {
  console.error(`expected fileBody and filePart POSTs, file=${fileCalls} part=${partCalls}`);
  process.exit(1);
}

if (fileName !== "notes.md" || fileBody !== "hello" || !fileMime.includes("text/plain")) {
  console.error(
    `expected Http.fileBody notes.md text/plain hello, got ${JSON.stringify({
      fileName,
      fileMime,
      fileBody,
    })}`
  );
  process.exit(1);
}

if (partName !== "notes.md" || partBody !== "hello" || !partMime.includes("text/plain")) {
  console.error(
    `expected Http.filePart doc=notes.md, got ${JSON.stringify({
      partName,
      partMime,
      partBody,
    })}`
  );
  process.exit(1);
}

if (innerText !== "ok|ok") {
  console.error(`expected expectWhatever Ok after file posts, got ${JSON.stringify(innerText)}`);
  process.exit(1);
}

helpers.buildImport("release")(programHandle);
if (boot.value) helpers.buildImport("release")(boot.value);
if (boot.initValue) helpers.buildImport("release")(boot.initValue);
if (boot.modelPtr) helpers.buildImport("release")(boot.modelPtr);

console.log("rc_ok http_file_body_ok");
