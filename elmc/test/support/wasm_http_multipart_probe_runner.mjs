import { readFileSync } from "node:fs";
import { parseHTML } from "linkedom";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";

const [buildDir] = process.argv.slice(2);
if (!buildDir) {
  console.error("usage: wasm_http_multipart_probe_runner.mjs <buildDir>");
  process.exit(2);
}

const { document } = parseHTML("<!doctype html><html><body><div id='app'></div></body></html>");
globalThis.document = document;
globalThis.window = document.defaultView;
globalThis.Node = document.defaultView.Node;

let bytesCalls = 0;
let uploadCalls = 0;
let uploadName = null;
let uploadBinType = null;

globalThis.fetch = async (url, init) => {
  const href = String(url);
  if (href.includes("/bytes")) {
    bytesCalls += 1;
    const buf = new Uint8Array([42]).buffer;
    return {
      ok: true,
      status: 200,
      statusText: "OK",
      url: href,
      headers: {
        forEach(fn) {
          fn("application/octet-stream", "content-type");
        },
        get: (k) => (k === "content-type" ? "application/octet-stream" : null),
      },
      text: async () => "",
      arrayBuffer: async () => buf,
    };
  }

  if (href.includes("/upload")) {
    uploadCalls += 1;
    const body = init?.body;
    if (typeof FormData !== "undefined" && body instanceof FormData) {
      uploadName = body.get("name");
      const bin = body.get("bin");
      uploadBinType = bin?.type ?? (bin ? "present" : null);
    }
    return {
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

await new Promise((r) => setTimeout(r, 80));

const innerText = document.getElementById("app")?.textContent ?? boot.innerText ?? "";
if (bytesCalls < 1 || uploadCalls < 1) {
  console.error(`expected expectBytes and multipart POST, bytes=${bytesCalls} upload=${uploadCalls}`);
  process.exit(1);
}
if (uploadName !== "ada") {
  console.error(`expected stringPart name=ada, got ${JSON.stringify(uploadName)}`);
  process.exit(1);
}
if (!uploadBinType) {
  console.error("expected bytesPart bin on FormData");
  process.exit(1);
}
if (innerText !== "42|ok") {
  console.error(
    `expected Http.expectBytes 42 and expectWhatever Ok (), got ${JSON.stringify(innerText)}`
  );
  process.exit(1);
}

helpers.buildImport("release")(programHandle);
if (boot.value) helpers.buildImport("release")(boot.value);
if (boot.initValue) helpers.buildImport("release")(boot.initValue);
if (boot.modelPtr) helpers.buildImport("release")(boot.modelPtr);

if (!helpers.checkBalanced()) {
  const state = helpers.debugRcState?.();
  if (state) {
    console.warn("RC imbalance after http multipart boot (non-fatal)", state);
  }
}

console.log("rc_ok http_multipart_ok");
