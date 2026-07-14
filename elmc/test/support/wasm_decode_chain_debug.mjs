import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { loadElmcWasm } from "../../../elmc-wasm-runtime/host/loader.js";

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "../../..");
const buildDir = process.argv[2] ?? "/tmp/elm_pebble_dev_wasm";

const manifest = JSON.parse(
  readFileSync(`${buildDir}/wasm/elmc_wasm.manifest.json`, "utf8")
);
const wasmBytes = readFileSync(`${buildDir}/wasm/app.wasm`);
const { helpers, callExport } = await loadElmcWasm({
  wasmBytes,
  manifestImports: manifest.imports || [],
  manifestClosures: manifest.closures || [],
  immortalStrings: manifest.immortal_strings || {},
});

const html = readFileSync(join(repoRoot, "elm_pebble_dev/dist/index.html"), "utf8");
const pageBytes = Buffer.from(
  html.match(/id="__ELM_PAGES_BYTES_DATA__"[^>]*>([^<]+)</)[1],
  "base64"
);
console.log("page bytes", [...pageBytes]);
const bytesHandle = helpers.newBytesFromUint8Array(new Uint8Array(pageBytes));

function invokeDecoder(decoderHandle, offset = 0) {
  const dec = helpers.readHandle(decoderHandle);
  const closure = dec.second;
  const payload = helpers.readHandle(closure);
  const entry = manifest.closures[payload.fnIndex];
  const offHandle = helpers.newInt(offset);
  const args = [...(payload.captures ?? []), bytesHandle, offHandle];
  const rc = helpers.callClosure(closure, args);
  const tup = helpers.readHandle(rc.value);
  const off = helpers.readHandle(tup?.first)?.value;
  const valTag = helpers.buildImport("union_tag_as_int")(tup?.second);
  return { rc: rc.rc, off, valTag, tup };
}

// BE endianness tuple (2, unit)
const beTuple = callExport("runtime_tuple2", [
  callExport("runtime_new_int", [2]).value,
  callExport("runtime_unit", []).value,
]).value;

const u32 = callExport("elmc_fn_Bytes_Decode_unsignedInt32", [beTuple]);
console.log("u32 decoder", u32.rc, helpers.readHandle(u32.value));
console.log("u32@0", invokeDecoder(u32.value, 0));

const rs = callExport("elmc_fn_Pages_Internal_ResponseSketch_w3_decode_ResponseSketch", [
  callExport("elmc_fn_Main_w3_decode_PageData", []).value,
  callExport("elmc_fn_Main_w3_decode_ActionData", []).value,
  callExport("elmc_fn_Shared_w3_decode_Data", []).value,
]).value;

const skip = callExport("elmc_fn_Main_skipFrozenViewsPrefix", [rs]);
console.log("skip decoder", skip.rc, helpers.readHandle(skip.value));
console.log("skip@0", invokeDecoder(skip.value, 0));

const decodeResponse = callExport("elmc_fn_Main_decodeResponse", []);
console.log("decodeResponse fn", decodeResponse.rc, helpers.readHandle(decodeResponse.value));
console.log("decodeResponse@0", invokeDecoder(decodeResponse.value, 0));

const bytesCmd = helpers.buildImport("bytes_cmd");
const scratch = 9000;
const outPtr = scratch;
const decPtr = scratch + 4;
const bytesPtr = scratch + 8;
const offPtr = scratch + 12;
helpers.storeHandle(decPtr, decodeResponse.value);
helpers.storeHandle(bytesPtr, bytesHandle);
helpers.storeHandle(offPtr, helpers.newInt(0));
const cmdRc = bytesCmd("decode", outPtr, decPtr, bytesPtr, offPtr);
const decoded = helpers.readHandle(helpers.loadHandle(outPtr));
console.log("bytes_cmd decode rc", cmdRc, "result", decoded);
