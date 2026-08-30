import { readFileSync } from "node:fs";
import { parseHTML } from "linkedom";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";

const [buildDir] = process.argv.slice(2);
if (!buildDir) {
  console.error("usage: wasm_http_risky_task_probe_runner.mjs <buildDir>");
  process.exit(2);
}

const { document } = parseHTML("<!doctype html><html><body><div id='app'></div></body></html>");
globalThis.document = document;
globalThis.window = document.defaultView;
globalThis.Node = document.defaultView.Node;

let fetchCalls = 0;
let lastCredentials = "";
globalThis.fetch = async (_url, init = {}) => {
  fetchCalls += 1;
  lastCredentials = String(init.credentials ?? "");
  return {
    ok: true,
    status: 200,
    statusText: "OK",
    url: "https://example.com/risky",
    headers: {
      forEach(fn) {
        fn("text/plain", "content-type");
      },
      get: (k) => (k === "content-type" ? "text/plain" : null),
    },
    text: async () => "ignored",
    arrayBuffer: async () => new TextEncoder().encode("ignored").buffer,
  };
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

let innerText = "";
const deadline = Date.now() + 400;
while (Date.now() < deadline) {
  innerText = document.getElementById("app")?.textContent ?? "";
  if (innerText && innerText !== "wait") break;
  await new Promise((r) => setTimeout(r, 20));
}
if (fetchCalls < 1) {
  console.error("expected Http.riskyTask to fetch");
  process.exit(1);
}
if (lastCredentials !== "include") {
  console.error(`expected official riskyTask credentials=include, got ${JSON.stringify(lastCredentials)}`);
  process.exit(1);
}
if (innerText !== "risky-ok") {
  console.error(`expected Task.attempt Ok from riskyTask, got ${JSON.stringify(innerText)}`);
  process.exit(1);
}

helpers.buildImport("release")(programHandle);
if (boot.value) helpers.buildImport("release")(boot.value);
if (boot.initValue) helpers.buildImport("release")(boot.initValue);
if (boot.modelPtr) helpers.buildImport("release")(boot.modelPtr);

console.log("rc_ok http_risky_task_ok");
