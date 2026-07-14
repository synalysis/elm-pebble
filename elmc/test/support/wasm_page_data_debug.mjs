import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "../../..");
const buildDir = process.argv[2] ?? "/tmp/elm_pebble_dev_wasm";

const manifest = JSON.parse(
  readFileSync(`${buildDir}/wasm/elmc_wasm.manifest.json`, "utf8")
);
const wasmBytes = readFileSync(`${buildDir}/wasm/app.wasm`);

const { helpers, callExport, instance } = await loadElmcWasm({
  wasmBytes,
  manifestImports: manifest.imports || [],
  manifestClosures: manifest.closures || [],
  immortalStrings: manifest.immortal_strings || {},
});

const html = readFileSync(join(repoRoot, "elm_pebble_dev/dist/index.html"), "utf8");
const match = html.match(/id="__ELM_PAGES_BYTES_DATA__"[^>]*>([^<]+)</);
const pageBytes = Buffer.from(match[1], "base64");
const bytesHandle = helpers.newBytesFromUint8Array(new Uint8Array(pageBytes));

const { value: programHandle } = callExport("elmc_fn_Main_main", []);
const bootInit = helpers.bootBrowserProgram(programHandle, {});
const initModel = bootInit.modelPtr;
const initRec = helpers.readHandle(initModel);
console.log("init field4", initRec.fields[4], helpers.readHandle(initRec.fields[4]));
console.log("init field13", initRec.fields[13], helpers.readHandle(initRec.fields[13]));

helpers.bootBrowserProgram(programHandle, {});
const msg = helpers.sendIncomingPort("pageDataFromJs", bytesHandle);
console.log("msg", msg.value, helpers.readHandle(msg.value));

const program = helpers.readHandle(programHandle);
const impl = helpers.readHandle(program.impl);
const updateFn = impl.fields[2];
console.log("updateFn", updateFn, helpers.readHandle(updateFn));
const updPayload = helpers.readHandle(updateFn);
if (!updPayload || updPayload.tag !== 5) {
  console.error("update fn is not a closure", updPayload);
  process.exit(1);
}
const entry = manifest.closures[updPayload.fnIndex];
const exportFn = instance.exports[entry.export];
const captures = updPayload.captures || [];
const result = exportFn(...captures, msg.value, initModel);
console.log("update rc", result[0], "out", result[1]);
const tup = helpers.readHandle(result[1]);
const model = tup?.first ?? result[1];
const rec = helpers.readHandle(model);
console.log("model", model, "field4", rec?.fields?.[4], helpers.readHandle(rec?.fields?.[4]));
console.log("field13", rec?.fields?.[13], helpers.readHandle(rec?.fields?.[13]));

// Try decodeResponse from config capture
const config = captures[0];
const configRec = helpers.readHandle(config);
console.log("config fields len", configRec?.fields?.length);
const decodeResponse = configRec?.fields?.[27];
console.log("decodeResponse", decodeResponse, helpers.readHandle(decodeResponse));

const { rc: decRc, value: decodeFn } = callExport("elmc_fn_Bytes_Decode_decode", []);
console.log("decode export", decRc, decodeFn, helpers.readHandle(decodeFn));
