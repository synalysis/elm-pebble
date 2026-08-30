import { readFileSync } from "node:fs";
import { parseHTML } from "linkedom";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";

const [buildDir] = process.argv.slice(2);
if (!buildDir) {
  console.error("usage: wasm_http_bytes_resolver_probe_runner.mjs <buildDir>");
  process.exit(2);
}

const { document } = parseHTML("<!doctype html><html><body><div id='app'></div></body></html>");
globalThis.document = document;
globalThis.window = document.defaultView;
globalThis.Node = document.defaultView.Node;

let fetchCalls = 0;
globalThis.fetch = async (_url, _init) => {
  fetchCalls += 1;
  const bytes = new Uint8Array([11, 22]);
  return {
    ok: true,
    status: 201,
    statusText: "Created",
    url: "https://example.com/bytes-task",
    headers: {
      forEach(fn) {
        fn("application/octet-stream", "content-type");
      },
      get: (k) => (k === "content-type" ? "application/octet-stream" : null),
    },
    text: async () => "not-bytes",
    arrayBuffer: async () => bytes.buffer,
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

await new Promise((r) => setTimeout(r, 80));

const innerText = document.getElementById("app")?.textContent ?? boot.innerText ?? "";
if (fetchCalls < 1) {
  console.error("expected Http.bytesResolver to fetch");
  process.exit(1);
}
const expected = "201:11:2";
if (innerText !== expected) {
  console.error(
    `expected official bytesResolver GoodStatus_ ${JSON.stringify(expected)}, got ${JSON.stringify(innerText)}`
  );
  process.exit(1);
}

helpers.buildImport("release")(programHandle);
if (boot.value) helpers.buildImport("release")(boot.value);
if (boot.initValue) helpers.buildImport("release")(boot.initValue);
if (boot.modelPtr) helpers.buildImport("release")(boot.modelPtr);

console.log("rc_ok http_bytes_resolver_ok");
