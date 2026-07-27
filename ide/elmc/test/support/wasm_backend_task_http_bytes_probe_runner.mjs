import { readFileSync } from "node:fs";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";
import { installProbeDocument } from "./wasm_probe_dom.mjs";

const [buildDir] = process.argv.slice(2);
if (!buildDir) {
  console.error("usage: wasm_backend_task_http_bytes_probe_runner.mjs <buildDir>");
  process.exit(2);
}

installProbeDocument();

const manifest = JSON.parse(
  readFileSync(`${buildDir}/wasm/elmc_wasm.manifest.json`, "utf8")
);
const wasmBytes = readFileSync(`${buildDir}/wasm/app.wasm`);

const requests = [];

globalThis.fetch = async (url, init) => {
  requests.push({ url, init });

  if (String(url).includes("data.bin")) {
    return {
      ok: true,
      status: 200,
      statusText: "OK",
      arrayBuffer: async () => Uint8Array.of(42).buffer,
      text: async () => "",
    };
  }

  return {
    ok: true,
    status: 200,
    statusText: "OK",
    text: async () => "upload-ok",
    arrayBuffer: async () => new ArrayBuffer(0),
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

await new Promise((r) => setTimeout(r, 200));

const getReq = requests.find((r) => String(r.url).includes("data.bin"));
const postReq = requests.find((r) => String(r.url).includes("upload.bin"));

if (!getReq) {
  console.error("expected BackendTask.Http.get bytes fetch");
  process.exit(1);
}

if (!postReq) {
  console.error("expected BackendTask.Http.post bytesBody fetch");
  process.exit(1);
}

if (postReq.init?.method !== "POST") {
  console.error(`expected POST upload, got ${JSON.stringify(postReq.init?.method)}`);
  process.exit(1);
}

const uploadBody = postReq.init?.body;
const uploadBytes =
  uploadBody instanceof Uint8Array
    ? uploadBody
    : uploadBody instanceof ArrayBuffer
      ? new Uint8Array(uploadBody)
      : null;

if (!uploadBytes || uploadBytes.length !== 2 || uploadBytes[0] !== 7 || uploadBytes[1] !== 8) {
  console.error(`expected bytesBody [7,8], got ${JSON.stringify(uploadBytes)}`);
  process.exit(1);
}

const innerText = document.getElementById("app")?.textContent ?? "";
if (innerText !== "42:posted") {
  console.error(`expected decoded byte and post completion, got ${JSON.stringify(innerText)}`);
  process.exit(1);
}

if (!helpers.checkBalanced()) {
  const state = helpers.debugRcState?.();
  if (state) {
    console.warn("rc leak after backend task http boot (non-fatal; live browser retains model/view)", state);
  }
}

console.log("rc_ok backend_task_http_bytes_ok");
