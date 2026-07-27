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
    closureCount: manifest.closure_count ?? null,
    closureCount: manifest.closure_count ?? null,
  immortalStrings: manifest.immortal_strings || {},
});

const unionTag = (p) => helpers.buildImport("union_tag_as_int")(p);

const d = (p, depth = 0) => {
  if (!p || depth > 4) return String(p);
  const h = helpers.readHandle(p);
  if (!h) return String(p);
  if (h.tag === 1) return `Int(${h.value})`;
  if (h.tag === 3) return h.value == null ? "Nothing" : `Just(${d(h.value, depth + 1)})`;
  if (h.tag === 6) return `T2(${d(h.first, depth + 1)}, ${d(h.second, depth + 1)})`;
  if (h.tag === 11)
    return `Rec(${h.fields.map((f, i) => `[${i}]=${d(f, depth + 1)}`).join(", ")})`;
  return `tag${h.tag}(${p})`;
};

const view = () => new DataView(memory.buffer);
const readOut = (p) => view().getUint32(p, true);

const html = readFileSync(join(repoRoot, "elm_pebble_dev/dist/index.html"), "utf8");
const pageBytes = Buffer.from(
  html.match(/id="__ELM_PAGES_BYTES_DATA__"[^>]*>([^<]+)</)[1],
  "base64"
);

const { value: programHandle } = callExport("elmc_fn_Main_main", []);
const bytesHandle = helpers.newBytesFromUint8Array(new Uint8Array(pageBytes));
const boot = helpers.bootBrowserProgram(programHandle, {
  incomingPorts: { pageDataFromJs: bytesHandle },
});

const platformModel = helpers.readHandle(boot.modelPtr);
const pageDataOk = helpers.readHandle(platformModel.fields[4]);
const sketch = helpers.readHandle(pageDataOk.value);
const userModel = helpers.readHandle(sketch.fields[0]);

const pageData = sketch.fields[1];
const sharedData = sketch.fields[2];
const maybePagePath = userModel.fields[2];

console.log("pageData tag", unionTag(pageData), d(pageData));
console.log("maybePagePath", d(maybePagePath));

helpers.buildImport("maybe_nothing")(8192);
const nothingGlobal = readOut(8192);

// PreRenderFlags = T2(Int(2), unit)
helpers.buildImport("json_cmd")(8196, 7);
const userFlags = readOut(8196);
helpers.buildImport("maybe_nothing")(8200);
const noAction = readOut(8200);

const init = callExport("elmc_fn_Main_init", [
  nothingGlobal,
  userFlags,
  sharedData,
  pageData,
  noAction,
  maybePagePath,
]);

console.log("Main.init rc", init.rc);
const initModel = helpers.readHandle(helpers.readHandle(init.value)?.first);
const pageUnion = helpers.readHandle(initModel?.fields?.[1]);
console.log("init model.page", d(pageUnion), "tag", unionTag(pageUnion));
console.log("expected ModelIndex tag 13, got", unionTag(pageUnion));

if (init.rc !== RC_SUCCESS || unionTag(pageUnion) !== 13) {
  process.exit(1);
}
