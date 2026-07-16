import { readFileSync } from "node:fs";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";

const [buildDir] = process.argv.slice(2);
if (!buildDir) {
  console.error("usage: wasm_backend_task_http_badbody_probe_runner.mjs <buildDir>");
  process.exit(2);
}

const manifest = JSON.parse(
  readFileSync(`${buildDir}/wasm/elmc_wasm.manifest.json`, "utf8")
);
const wasmBytes = readFileSync(`${buildDir}/wasm/app.wasm`);

globalThis.fetch = async () => ({
  ok: true,
  status: 200,
  statusText: "OK",
  url: "https://example.com/broken.json",
  text: async () => "{}",
});

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

const innerText = document.getElementById("app")?.textContent ?? "";
if (!innerText.startsWith("bad-body:")) {
  console.error(
    `expected BadBody error label in view, got innerText=${JSON.stringify(innerText)}`
  );
  process.exit(1);
}

if (!innerText.includes("field `stars`")) {
  console.error(`expected Field decode error for stars, got ${JSON.stringify(innerText)}`);
  process.exit(1);
}

if (!helpers.checkBalanced()) {
  console.error("RC imbalance after backend task http badbody boot");
  process.exit(1);
}

console.log("rc_ok backend_task_http_badbody_ok");
