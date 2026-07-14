import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { loadElmcWasm } from "../../../elmc-wasm-runtime/host/loader.js";

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "../../..");
const buildDir = process.argv[2] ?? "/tmp/elm_pebble_dev_wasm";
const manifest = JSON.parse(readFileSync(`${buildDir}/wasm/elmc_wasm.manifest.json`, "utf8"));
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
    return `Rec(f4=${d(f4)}, f13=${d(f13)})`;
  }
  if (h.tag === 16) return `Bytes(${h.view?.byteLength})`;
  return `tag${h.tag}(${p})`;
};

const html = readFileSync(join(repoRoot, "elm_pebble_dev/dist/index.html"), "utf8");
const pageBytes = Buffer.from(html.match(/id="__ELM_PAGES_BYTES_DATA__"[^>]*>([^<]+)</)[1], "base64");
const { value: programHandle } = callExport("elmc_fn_Main_main", []);
const bytesHandle = helpers.newBytesFromUint8Array(new Uint8Array(pageBytes));

const boot0 = helpers.bootBrowserProgram(programHandle, {});
console.log("init:", d(boot0.modelPtr));

const boot = helpers.bootBrowserProgram(programHandle, {
  incomingPorts: { pageDataFromJs: bytesHandle },
});
console.log("after port boot title:", boot.title);
console.log("model:", d(boot.modelPtr));

const dr = callExport("elmc_fn_Main_decodeResponse", []);
const scratch = 9024;
helpers.buildImport("bytes_cmd")(scratch, 5, dr.value, bytesHandle);
const readOut = (p) => new DataView(memory.buffer).getUint32(p, true);
console.log("decodeResponse bytes_cmd:", d(readOut(scratch)));
