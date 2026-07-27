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
const { helpers, callExport, memory, instance } = await loadElmcWasm({
  wasmBytes,
  manifestImports: manifest.imports || [],
  manifestClosures: manifest.closures || [],
    closureCount: manifest.closure_count ?? null,
    closureCount: manifest.closure_count ?? null,
  immortalStrings: manifest.immortal_strings || {},
});

const unionTag = (p) => helpers.buildImport("union_tag_as_int")(p);
const tagMatches = (subject, tag) => {
  const s = 9000;
  helpers.buildImport("union_tag_matches")(s, subject, tag);
  return new DataView(memory.buffer).getUint32(s, true);
};
const readOut = (p) => new DataView(memory.buffer).getUint32(p, true);

const d = (p) => {
  const h = helpers.readHandle(p);
  if (!h) return String(p);
  if (h.tag === 1) return `Int(${h.value})`;
  if (h.tag === 3) return h.value == null ? "Nothing" : `Just(${d(h.value)})`;
  if (h.tag === 6) return `T2(${d(h.first)}, ${d(h.second)})`;
  return `tag${h.tag}(${p})`;
};

const html = readFileSync(join(repoRoot, "elm_pebble_dev/dist/index.html"), "utf8");
const pageBytes = Buffer.from(
  html.match(/id="__ELM_PAGES_BYTES_DATA__"[^>]*>([^<]+)</)[1],
  "base64"
);
const boot = helpers.bootBrowserProgram(callExport("elmc_fn_Main_main", []).value, {
  incomingPorts: { pageDataFromJs: helpers.newBytesFromUint8Array(new Uint8Array(pageBytes)) },
});

const platformModel = helpers.readHandle(boot.modelPtr);
const sketch = helpers.readHandle(helpers.readHandle(platformModel.fields[4]).value);
const userModel = helpers.readHandle(sketch.fields[0]);
const pageData = sketch.fields[1];
const maybePP = helpers.readHandle(userModel.fields[2]);
const rec = maybePP.value;

helpers.buildImport("record_get")(8192, rec, 1);
const metaMaybe = readOut(8192);
helpers.buildImport("record_get")(8196, rec, 0);
const pathRec = readOut(8196);
helpers.buildImport("maybe_just_own")(8200, pathRec, 0);
const pathMaybe = readOut(8200);

console.log("metadata field", d(metaMaybe));
console.log("path maybe", d(pathMaybe));

// Simulate map2 via runtime
const pairCl = instance.exports.elmc_fn_Main_init_closure_1;
const metaPayload = helpers.readHandle(metaMaybe)?.value;
const pathPayload = helpers.readHandle(pathMaybe)?.value;
let map2Pair;
if (metaPayload != null && pathPayload != null) {
  const r = pairCl(metaPayload, pathPayload);
  map2Pair = helpers.readHandle(r[1]);
} else {
  console.log("map2 would be Nothing");
}

if (map2Pair) {
  const route = map2Pair.first;
  const path = map2Pair.second;
  console.log("map2 route", d(route), "tag", unionTag(route), "m13", tagMatches(route, 13));
  console.log("pageData", d(pageData), "tag", unionTag(pageData), "m13", tagMatches(pageData, 13));
  console.log("both match 13?", tagMatches(route, 13) && tagMatches(pageData, 13));
}

// Check handle-13 collision at tag test time
console.log("handle 13 at diagnose time", d(helpers.readHandle(13) ?? "free"));

helpers.buildImport("maybe_nothing")(8212);
const nothingGlobal = readOut(8212);
helpers.buildImport("json_cmd")(8216, 7);
const userFlags = readOut(8216);
helpers.buildImport("maybe_nothing")(8220);
const noAction = readOut(8220);

const init = callExport("elmc_fn_Main_init", [
  nothingGlobal,
  userFlags,
  sketch.fields[2],
  pageData,
  noAction,
  maybePP,
]);
const pageUnion = helpers.readHandle(helpers.readHandle(init.value)?.first)?.fields?.[1];
console.log("init page tag", unionTag(pageUnion), d(pageUnion));
