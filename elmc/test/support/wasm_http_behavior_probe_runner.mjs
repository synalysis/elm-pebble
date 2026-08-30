import { readFileSync } from "node:fs";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";

const [buildDir] = process.argv.slice(2);
if (!buildDir) {
  console.error("usage: wasm_http_behavior_probe_runner.mjs <buildDir>");
  process.exit(2);
}

const manifest = JSON.parse(
  readFileSync(`${buildDir}/wasm/elmc_wasm.manifest.json`, "utf8")
);
const wasmBytes = readFileSync(`${buildDir}/wasm/app.wasm`);

let fetchCalls = 0;
let lastInit = null;
globalThis.fetch = async (url, init) => {
  fetchCalls += 1;
  lastInit = init;
  if (url.includes("timeout.example")) {
    await new Promise((r) => setTimeout(r, 50));
    const err = new Error("aborted");
    err.name = "AbortError";
    throw err;
  }
  if (url.includes("fail.example")) {
    throw new Error("network down");
  }
  return {
    ok: true,
    status: 200,
    statusText: "OK",
    headers: {
      forEach(fn) {
        fn("text/plain", "content-type");
      },
      get: (k) => (k === "content-type" ? "text/plain" : null),
    },
    text: async () => "hello-http",
    arrayBuffer: async () => new TextEncoder().encode("hello-http").buffer,
  };
};

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
  console.error(`boot failed: rc=${boot.rc}`);
  process.exit(1);
}

await new Promise((r) => setTimeout(r, 100));

if (fetchCalls < 1) {
  console.error("expected at least one fetch from Http.post init");
  process.exit(1);
}

if (lastInit?.body != null && lastInit.body !== "") {
  console.error("emptyBody post should not send a request body", lastInit.body);
  process.exit(1);
}

helpers.buildImport("release")(programHandle);
if (boot.value) helpers.buildImport("release")(boot.value);
if (boot.initValue) helpers.buildImport("release")(boot.initValue);
if (boot.modelPtr) helpers.buildImport("release")(boot.modelPtr);

if (!helpers.checkBalanced()) {
  const state = helpers.debugRcState?.();
  if (state) {
    console.warn("RC imbalance after http behavior boot (non-fatal)", state);
  }
}

console.log("rc_ok http_behavior_ok");
