import { readFileSync } from "node:fs";
import { loadElmcWasm } from "../../../elmc-wasm-runtime/host/loader.js";

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

const html = readFileSync("elm_pebble_dev/dist/index.html", "utf8");
const bytes = Buffer.from(
  html.match(/id="__ELM_PAGES_BYTES_DATA__"[^>]*>([^<]+)</)[1],
  "base64"
);
const bytesHandle = helpers.newBytesFromUint8Array(new Uint8Array(bytes));

const rs = callExport("elmc_fn_Pages_Internal_ResponseSketch_w3_decode_ResponseSketch", [
  callExport("elmc_fn_Main_w3_decode_PageData", []).value,
  callExport("elmc_fn_Main_w3_decode_ActionData", []).value,
  callExport("elmc_fn_Shared_w3_decode_Data", []).value,
]).value;

const skip = callExport("elmc_fn_Main_skipFrozenViewsPrefix", [rs]);
const inner = helpers.readHandle(skip.value).second;
const payload = helpers.readHandle(inner);
console.log("andThen lam fn", payload.fnIndex, manifest.closures[payload.fnIndex]?.export);
console.log("captures", payload.captures);

const entry = manifest.closures[payload.fnIndex];
const exportFn = instance.exports[entry.export];

// andThen_lam_0_closure_0 arity 4: callback, decoderA, bytes, offset
// invokeClosure only passes captures + 2 args - need 4 params total
// WASM closure: captures + call args. arity 4 means 4 call args after captures?
// payload.arity=2 from decodeResponse - might be partial application

const initOff = helpers.buildImport("new_int");
// use scratch via bytes_cmd path - call with captures from boot
const scratch = 9000;
initOff(scratch, 0);
const offHandle = new DataView(instance.exports.memory.buffer).getUint32(scratch, true);

const result = exportFn(...(payload.captures ?? []), bytesHandle, offHandle);
console.log("andThen lam rc", result[0], "out", result[1]);
const tup = helpers.readHandle(result[1]);
console.log(
  "off",
  helpers.readHandle(tup?.first)?.value,
  "union",
  helpers.buildImport("union_tag_as_int")(tup?.second)
);
