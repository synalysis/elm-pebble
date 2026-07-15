import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";
import { decodePageBytesFromHtml } from "../../../elmc-wasm-runtime/host/page_bytes.js";

const buildDir = process.argv[2] ?? "dist/wasm-web";
const indexHtml = process.argv[3] ?? "dist/index.html";

const manifest = JSON.parse(readFileSync(`${buildDir}/wasm/elmc_wasm.manifest.json`, "utf8"));
const wasmBytes = readFileSync(`${buildDir}/wasm/app.wasm`);
const pageBytes = decodePageBytesFromHtml(readFileSync(indexHtml, "utf8"));

const { helpers, callExport } = await loadElmcWasm({
  wasmBytes,
  manifestImports: manifest.imports || [],
  manifestClosures: manifest.closures || [],
  immortalStrings: manifest.immortal_strings || {},
});

const { rc, value } = callExport("elmc_fn_Main_main", []);
if (rc !== RC_SUCCESS) process.exit(1);

const bytesHandle = helpers.newBytesFromUint8Array(pageBytes);
const boot = helpers.bootBrowserProgram(value, {
  incomingPorts: { pageDataFromJs: bytesHandle },
});

console.log("boot", { rc: boot.rc, stage: boot.stage, title: boot.title });
console.log("innerText len", boot.innerText?.length, boot.innerText?.slice(0, 200));

const viewPayload = helpers.readHandle(boot.value);
console.log("view tag", viewPayload?.tag, "fields", viewPayload?.fields?.length);

if (viewPayload?.tag === 11 && viewPayload.fields?.length >= 2) {
  const bodyPtr = viewPayload.fields[1];
  const bodyPayload = helpers.readHandle(bodyPtr);
  console.log("body tag", bodyPayload?.tag, "items", bodyPayload?.items?.length);
  for (let i = 0; i < Math.min(5, bodyPayload?.items?.length ?? 0); i++) {
    const child = bodyPayload.items[i];
    const payload = helpers.readHandle(child);
    console.log(
      `body[${i}] tag=${payload?.tag} inspect=${JSON.stringify(helpers.inspectVdom(child))}`
    );
  }
}
