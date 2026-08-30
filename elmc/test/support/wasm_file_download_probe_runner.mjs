import { readFileSync } from "node:fs";
import { parseHTML } from "linkedom";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";

const [buildDir] = process.argv.slice(2);
if (!buildDir) {
  console.error("usage: wasm_file_download_probe_runner.mjs <buildDir>");
  process.exit(2);
}

const { document, window } = parseHTML(
  "<!doctype html><html><body><div id='app'></div></body></html>"
);
globalThis.document = document;
globalThis.window = window;
globalThis.Node = window.Node;

if (typeof Blob === "undefined") {
  globalThis.Blob = class Blob {
    constructor(parts = [], opts = {}) {
      this._parts = parts;
      this.type = opts.type || "";
    }
    async arrayBuffer() {
      const chunks = this._parts.map((part) => {
        if (part instanceof ArrayBuffer) return new Uint8Array(part);
        if (ArrayBuffer.isView(part)) {
          return new Uint8Array(part.buffer, part.byteOffset, part.byteLength);
        }
        return new TextEncoder().encode(String(part));
      });
      const total = chunks.reduce((n, chunk) => n + chunk.byteLength, 0);
      const out = new Uint8Array(total);
      let offset = 0;
      for (const chunk of chunks) {
        out.set(chunk, offset);
        offset += chunk.byteLength;
      }
      return out.buffer;
    }
    async text() {
      return new TextDecoder().decode(await this.arrayBuffer());
    }
  };
}

const blobByUrl = new Map();
const origCreateURL =
  typeof URL.createObjectURL === "function" ? URL.createObjectURL.bind(URL) : null;
URL.createObjectURL = (blob) => {
  const url = origCreateURL ? origCreateURL(blob) : `blob:elmc-probe/${blobByUrl.size}`;
  blobByUrl.set(url, blob);
  return url;
};
if (typeof URL.revokeObjectURL !== "function") {
  URL.revokeObjectURL = (url) => blobByUrl.delete(url);
}

const clicks = [];
const origCreateElement = document.createElement.bind(document);
document.createElement = function createElement(tag, ...rest) {
  const el = origCreateElement(tag, ...rest);
  if (String(tag).toLowerCase() === "a") {
    const origClick = typeof el.click === "function" ? el.click.bind(el) : () => {};
    el.click = function click() {
      clicks.push({ href: String(el.href || ""), download: String(el.download || "") });
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

const byName = Object.fromEntries(clicks.map((click) => [click.download, click]));
if (!byName["draft.md"] || !byName["blob.bin"] || clicks.length !== 2) {
  console.error(
    `expected File.Download.string and bytes <a> clicks, got ${JSON.stringify(clicks)}`
  );
  process.exit(1);
}

const stringBlob = blobByUrl.get(byName["draft.md"].href);
const stringText =
  stringBlob && typeof stringBlob.text === "function"
    ? await stringBlob.text()
    : stringBlob
      ? String(stringBlob)
      : "";
if (stringText !== "hello") {
  console.error(
    `expected download body "hello", got ${JSON.stringify(stringText)} href=${byName["draft.md"].href}`
  );
  process.exit(1);
}

if (stringBlob?.type && stringBlob.type !== "text/plain") {
  console.error(`expected mime text/plain, got ${JSON.stringify(stringBlob.type)}`);
  process.exit(1);
}

const bytesBlob = blobByUrl.get(byName["blob.bin"].href);
if (!bytesBlob || typeof bytesBlob.arrayBuffer !== "function") {
  console.error(`expected File.Download.bytes blob, got ${JSON.stringify(byName["blob.bin"])}`);
  process.exit(1);
}
const bytes = new Uint8Array(await bytesBlob.arrayBuffer());
if (bytes.length !== 1 || bytes[0] !== 42) {
  console.error(`expected bytes [42], got ${JSON.stringify(Array.from(bytes))}`);
  process.exit(1);
}
if (bytesBlob.type && bytesBlob.type !== "application/octet-stream") {
  console.error(`expected mime application/octet-stream, got ${JSON.stringify(bytesBlob.type)}`);
  process.exit(1);
}

helpers.buildImport("release")(programHandle);
if (boot.value) helpers.buildImport("release")(boot.value);
if (boot.initValue) helpers.buildImport("release")(boot.initValue);
if (boot.modelPtr) helpers.buildImport("release")(boot.modelPtr);

console.log("rc_ok file_download_ok");
