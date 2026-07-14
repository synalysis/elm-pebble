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
const { helpers, callExport, memory } = await loadElmcWasm({
  wasmBytes,
  manifestImports: manifest.imports || [],
  manifestClosures: manifest.closures || [],
  immortalStrings: manifest.immortal_strings || {},
});

const d = (p) => {
  const h = helpers.readHandle(p);
  if (!h) return String(p);
  if (h.tag === 1) return `Int(${h.value})`;
  if (h.tag === 3) return h.value == null ? "Nothing" : `Just(${d(h.value)})`;
  if (h.tag === 6) return `T2(${d(h.first)}, ${d(h.second)})`;
  if (h.tag === 8) return h.isOk ? `Ok(${d(h.value)})` : `Err(${d(h.value)})`;
  if (h.tag === 11) {
    const f4 = h.fields?.[4];
    const f13 = h.fields?.[13];
    const f27 = h.fields?.[27];
    return `Rec(f4=${d(f4)}, f13=${d(f13)}, f27=${d(f27)?.slice?.(0, 80) ?? d(f27)})`;
  }
  if (h.tag === 16) return `Bytes(${h.view?.byteLength})`;
  return `tag${h.tag}(${p})`;
};

const unionTag = (p) => helpers.buildImport("union_tag_as_int")(p);
const readOut = (p) => new DataView(memory.buffer).getUint32(p, true);

const html = readFileSync(join(repoRoot, "elm_pebble_dev/dist/index.html"), "utf8");
const pageBytes = Buffer.from(
  html.match(/id="__ELM_PAGES_BYTES_DATA__"[^>]*>([^<]+)</)[1],
  "base64"
);

const { value: programHandle } = callExport("elmc_fn_Main_main", []);
const bytesHandle = helpers.newBytesFromUint8Array(new Uint8Array(pageBytes));

const boot0 = helpers.bootBrowserProgram(programHandle, {});
const initModel = helpers.readHandle(boot0.modelPtr);
console.log("init model:", d(boot0.modelPtr));

const portMsg = helpers.sendIncomingPort("pageDataFromJs", bytesHandle);
console.log("port msg rc", portMsg.rc, "msg:", d(portMsg.value), "tag", unionTag(portMsg.value));

const program = helpers.readHandle(programHandle);
const implRec = helpers.readHandle(program?.impl);
const initFn = implRec?.fields?.[0];
const initPayload = helpers.readHandle(initFn);
const config = initPayload?.captures?.[0];
const updateClosure = implRec?.fields?.[2];
console.log("config:", d(config));
console.log("update closure:", d(updateClosure));

const scratch = 9000;
helpers.buildImport("call_closure")(
  scratch,
  2,
  updateClosure,
  portMsg.value,
  boot0.modelPtr
);
const updateRc = new DataView(memory.buffer).getInt32(scratch + 4, true);
const updateOut = readOut(scratch);
console.log("update rc", updateRc, "result:", d(updateOut));

if (updateRc === RC_SUCCESS) {
  const tup = helpers.readHandle(updateOut);
  const newModel = tup?.first;
  console.log("new model:", d(newModel));
  const nm = helpers.readHandle(newModel);
  console.log("pageData f4:", d(nm?.fields?.[4]));
  console.log("pending f13:", d(nm?.fields?.[13]));
}

// decode with config decoder (field 27 on config record)
const cfgRec = helpers.readHandle(config);
const cfgDecoder = cfgRec?.fields?.[27];
const mainDecoder = callExport("elmc_fn_Main_decodeResponse", []).value;
console.log("config.decodeResponse same as Main?", cfgDecoder === mainDecoder);
console.log("config decoder:", d(cfgDecoder));
console.log("main decoder:", d(mainDecoder));

const decScratch = 9024;
helpers.buildImport("bytes_cmd")(decScratch, 5, cfgDecoder ?? mainDecoder, bytesHandle);
const decoded = readOut(decScratch);
const decPayload = helpers.readHandle(decoded);
console.log(
  "bytes_cmd with config decoder:",
  d(decoded),
  "just payload tag",
  decPayload?.value != null ? unionTag(decPayload.value) : "n/a"
);
