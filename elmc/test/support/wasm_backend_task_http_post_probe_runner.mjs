import { readFileSync } from "node:fs";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";

const [buildDir] = process.argv.slice(2);
if (!buildDir) {
  console.error("usage: wasm_backend_task_http_post_probe_runner.mjs <buildDir>");
  process.exit(2);
}

const manifest = JSON.parse(
  readFileSync(`${buildDir}/wasm/elmc_wasm.manifest.json`, "utf8")
);
const wasmBytes = readFileSync(`${buildDir}/wasm/app.wasm`);

let lastRequest = null;

globalThis.fetch = async (url, init) => {
  lastRequest = { url, init };
  return {
    ok: true,
    status: 200,
    statusText: "OK",
    text: async () => "ignored-body",
  };
};

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
  console.error(`boot failed: rc=${boot.rc}`);
  process.exit(1);
}

await new Promise((r) => setTimeout(r, 150));

if (!lastRequest) {
  console.error("expected BackendTask.Http.post to fetch");
  process.exit(1);
}

if (lastRequest.init?.method !== "POST") {
  console.error(`expected POST method, got ${JSON.stringify(lastRequest.init?.method)}`);
  process.exit(1);
}

const contentType =
  typeof lastRequest.init?.headers?.get === "function"
    ? lastRequest.init.headers.get("Content-Type")
    : null;
if (contentType !== "application/json") {
  console.error(`expected application/json content type, got ${JSON.stringify(contentType)}`);
  process.exit(1);
}

const bodyText = lastRequest.init?.body ?? "";
let parsed;
try {
  parsed = JSON.parse(bodyText);
} catch (_err) {
  console.error(`expected JSON request body, got ${JSON.stringify(bodyText)}`);
  process.exit(1);
}

if (parsed?.name !== "test") {
  console.error(`expected JSON body name=test, got ${JSON.stringify(parsed)}`);
  process.exit(1);
}

const innerText = document.getElementById("app")?.textContent ?? "";
if (innerText !== "posted") {
  console.error(`expected posted view after expectWhatever, got ${JSON.stringify(innerText)}`);
  process.exit(1);
}

if (!helpers.checkBalanced()) {
  console.error("RC imbalance after backend task http post boot");
  process.exit(1);
}

console.log("rc_ok backend_task_http_post_ok");
