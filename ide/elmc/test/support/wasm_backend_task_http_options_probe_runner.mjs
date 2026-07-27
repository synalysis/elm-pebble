import { readFileSync } from "node:fs";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";
import { installProbeDocument } from "./wasm_probe_dom.mjs";

const [buildDir] = process.argv.slice(2);
if (!buildDir) {
  console.error("usage: wasm_backend_task_http_options_probe_runner.mjs <buildDir>");
  process.exit(2);
}

installProbeDocument();

const manifest = JSON.parse(
  readFileSync(`${buildDir}/wasm/elmc_wasm.manifest.json`, "utf8")
);
const wasmBytes = readFileSync(`${buildDir}/wasm/app.wasm`);

let fetchCalls = 0;

globalThis.fetch = async (_url, init) => {
  fetchCalls += 1;
  if (fetchCalls === 1) {
    throw new Error("temporary network failure");
  }

  const headers = init?.headers;
  const testHeader =
    typeof headers?.get === "function"
      ? headers.get("X-Test-Header")
      : headers?.["X-Test-Header"];
  if (testHeader !== "probe") {
    console.error(`expected X-Test-Header request header, got ${JSON.stringify(testHeader)}`);
    process.exit(1);
  }

  return {
    ok: true,
    status: 200,
    statusText: "OK",
    text: async () => JSON.stringify({ stars: 42 }),
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

await new Promise((r) => setTimeout(r, 150));

if (fetchCalls < 2) {
  console.error(`expected BackendTask.Http retries to re-fetch after failure, got ${fetchCalls} calls`);
  process.exit(1);
}

const innerText = document.getElementById("app")?.textContent ?? "";
if (innerText !== "620") {
  console.error(
    `expected nested withMetadata statusCode + (stars * 10) in view, got innerText=${JSON.stringify(innerText)}`
  );
  process.exit(1);
}

if (!helpers.checkBalanced()) {
  const state = helpers.debugRcState?.();
  if (state) {
    console.warn("rc leak after backend task http boot (non-fatal; live browser retains model/view)", state);
  }
}

console.log("rc_ok backend_task_http_options_ok");
