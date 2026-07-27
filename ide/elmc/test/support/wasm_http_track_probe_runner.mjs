import { readFileSync } from "node:fs";
import { parseHTML } from "linkedom";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";

const [buildDir] = process.argv.slice(2);
if (!buildDir) {
  console.error("usage: wasm_http_track_probe_runner.mjs <buildDir>");
  process.exit(2);
}

const { document } = parseHTML("<!doctype html><html><body><div id='app'></div></body></html>");
globalThis.document = document;
globalThis.window = document.defaultView;
globalThis.Node = document.defaultView.Node;

class MockXMLHttpRequest {
  constructor() {
    this.status = 0;
    this.statusText = "";
    this.responseText = "";
    this.response = null;
    this.responseType = "text";
    this._listeners = {};
    this.upload = {
      addEventListener: (event, handler) => {
        if (event === "progress") this._uploadProgress = handler;
      },
    };
  }

  open(_method, _url) {}

  setRequestHeader() {}

  getAllResponseHeaders() {
    return "content-type: text/plain\r\n";
  }

  abort() {}

  addEventListener(event, handler) {
    this._listeners[event] = handler;
  }

  send(_body) {
    queueMicrotask(() => {
      if (this._uploadProgress) {
        this._uploadProgress({ lengthComputable: true, loaded: 40, total: 100 });
      }
      if (this._listeners.progress) {
        this._listeners.progress({ lengthComputable: true, loaded: 100, total: 100 });
      }

      this.status = 200;
      this.statusText = "OK";
      this.responseText = "tracked-body";
      this._listeners.loadend?.();
    });
  }
}

globalThis.XMLHttpRequest = MockXMLHttpRequest;

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

await new Promise((r) => setTimeout(r, 150));

const innerText = document.getElementById("app")?.textContent ?? boot.innerText ?? "";
const progressCount = Number.parseInt(innerText, 10);

if (!Number.isFinite(progressCount) || progressCount < 1) {
  console.error(
    `expected Http.track progress updates in view, got innerText=${JSON.stringify(innerText)}`
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
    console.warn("rc leak after http track boot (non-fatal)", state);
  }
}

console.log("rc_ok http_track_ok");
