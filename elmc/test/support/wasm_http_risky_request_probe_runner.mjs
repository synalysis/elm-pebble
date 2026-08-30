import { readFileSync } from "node:fs";
import { parseHTML } from "linkedom";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";

const [buildDir] = process.argv.slice(2);
if (!buildDir) {
  console.error("usage: wasm_http_risky_request_probe_runner.mjs <buildDir>");
  process.exit(2);
}

const { document } = parseHTML("<!doctype html><html><body><div id='app'></div></body></html>");
globalThis.document = document;
globalThis.window = document.defaultView;
globalThis.Node = document.defaultView.Node;

const headerValue = (headers, name) => {
  if (!headers) return "";
  if (typeof headers.get === "function") return String(headers.get(name) ?? "");
  const key = Object.keys(headers).find((k) => k.toLowerCase() === name.toLowerCase());
  return key ? String(headers[key] ?? "") : "";
};

const bodyText = (body) => {
  if (typeof body === "string") return body;
  if (body instanceof Uint8Array) return new TextDecoder().decode(body);
  if (body instanceof ArrayBuffer) return new TextDecoder().decode(body);
  if (ArrayBuffer.isView(body)) return new TextDecoder().decode(body);
  return "";
};

let fetchCalls = 0;
let lastInit = null;
globalThis.fetch = async (_url, init = {}) => {
  fetchCalls += 1;
  lastInit = { ...init };
  return {
    ok: true,
    status: 200,
    statusText: "OK",
    url: "https://example.com/json",
    headers: {
      forEach(fn) {
        fn("application/json", "content-type");
      },
      get: (k) => (k === "content-type" ? "application/json" : null),
    },
    text: async () => "json-ok",
    arrayBuffer: async () => new TextEncoder().encode("json-ok").buffer,
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
  console.error("expected Http.riskyRequest to fetch");
  process.exit(1);
}

const credentials = String(lastInit?.credentials ?? "");
const method = String(lastInit?.method ?? "").toUpperCase();
const contentType = headerValue(lastInit?.headers, "Content-Type");
const body = bodyText(lastInit?.body);
if (
  credentials !== "include" ||
  method !== "POST" ||
  !contentType.includes("application/json") ||
  body !== '{"n":7}'
) {
  console.error(
    `expected risky POST jsonBody {"n":7}, got ${JSON.stringify({
      credentials,
      method,
      contentType,
      body,
    })}`
  );
  process.exit(1);
}

if (innerText !== "json-ok") {
  console.error(`expected expectString json-ok, got ${JSON.stringify(innerText)}`);
  process.exit(1);
}

helpers.buildImport("release")(programHandle);
if (boot.value) helpers.buildImport("release")(boot.value);
if (boot.initValue) helpers.buildImport("release")(boot.initValue);
if (boot.modelPtr) helpers.buildImport("release")(boot.modelPtr);

console.log("rc_ok http_risky_request_ok");
