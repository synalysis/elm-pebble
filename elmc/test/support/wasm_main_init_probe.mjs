import { readFileSync } from "node:fs";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";

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

const d = (p, depth = 0) => {
  if (!p || depth > 4) return String(p);
  const h = helpers.readHandle(p);
  if (!h) return "null";
  if (h.tag === 1) return `Int(${h.value})`;
  if (h.tag === 7) return `Str(${JSON.stringify(h.value)})`;
  if (h.tag === 3) return h.value == null ? "Nothing" : `Just(${d(h.value, depth + 1)})`;
  if (h.tag === 6) return `T2(${d(h.first, depth + 1)}, ${d(h.second, depth + 1)})`;
  if (h.tag === 11) return `Rec(${ (h.fields ?? []).map((f, i) => `[${i}]=${d(f, depth + 1)}`).join(", ") })`;
  return `tag${h.tag}`;
};

const view = () => new DataView(memory.buffer);
const readOut = (p) => view().getUint32(p, true);

const boot0 = helpers.bootBrowserProgram(
  (await callExport("elmc_fn_Main_main", [])).value,
  {}
);
const url = helpers.readHandle(boot0.modelPtr)?.fields?.[1];
const route = callExport("elmc_fn_Route_urlToRoute", [url]);
console.log("urlToRoute", d(route.value));

helpers.buildImport("maybe_nothing")(8192);
const nothing = readOut(8192);
helpers.buildImport("list_nil")(8196);
const emptyPath = readOut(8196);
helpers.buildImport("maybe_nothing")(8200);
const noQuery = readOut(8200);
helpers.buildImport("maybe_nothing")(8204);
const noFragment = readOut(8204);

// { path = { path, query, fragment }, metadata, pageUrl = Nothing }
helpers.buildImport("record_new")(8208, emptyPath, noQuery, noFragment);
const pathRec = readOut(8208);
helpers.buildImport("record_new")(8212, pathRec, route.value, nothing);
const pagePathRec = readOut(8212);
helpers.buildImport("maybe_just_own")(8216, pagePathRec, 1);
const maybePagePath = readOut(8216);

const html = readFileSync("elm_pebble_dev/dist/index.html", "utf8");
const pageBytes = Buffer.from(
  html.match(/id="__ELM_PAGES_BYTES_DATA__"[^>]*>([^<]+)</)[1],
  "base64"
);
const bytesHandle = helpers.newBytesFromUint8Array(new Uint8Array(pageBytes));
const cfgDecoder = helpers.readHandle(
  helpers.readHandle(
    helpers.readHandle((await callExport("elmc_fn_Main_main", [])).value)?.impl
  )?.fields?.[0]
)?.captures?.[0];
const cfgRec = helpers.readHandle(cfgDecoder);
const decodeFn = cfgRec?.fields?.[27] ?? callExport("elmc_fn_Main_decodeResponse", []).value;
helpers.buildImport("bytes_cmd")(8220, 5, decodeFn, bytesHandle);
const decoded = readOut(8220);
console.log("decoded", d(decoded));

const justPayload = helpers.readHandle(decoded)?.value;
const hot = helpers.readHandle(justPayload);
const pageData = hot?.first;
const sharedData = helpers.readHandle(hot?.second)?.first;
const actionData = helpers.readHandle(hot?.second)?.second;

helpers.buildImport("json_cmd")(8224, 7);
const userFlags = readOut(8224);

const init = callExport("elmc_fn_Main_init", [
  nothing,
  userFlags,
  sharedData,
  pageData,
  actionData,
  maybePagePath,
]);
console.log("Main.init rc", init.rc);
const initTup = helpers.readHandle(init.value);
console.log("Main.init model", d(initTup?.first));
console.log("Main.init page union tag", helpers.buildImport("union_tag_as_int")(initTup?.first));
