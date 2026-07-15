import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { loadElmcWasm } from "../../../elmc-wasm-runtime/host/loader.js";

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "../../..");
const buildDir = process.argv[2] ?? "/tmp/elm_pebble_dev_wasm";
const manifest = JSON.parse(readFileSync(`${buildDir}/wasm/elmc_wasm.manifest.json`, "utf8"));
const wasmBytes = readFileSync(`${buildDir}/wasm/app.wasm`);
const { helpers, callExport, instance, memory } = await loadElmcWasm({
  wasmBytes,
  manifestImports: manifest.imports || [],
  manifestClosures: manifest.closures || [],
  immortalStrings: manifest.immortal_strings || {},
});

const unionTag = (p) => helpers.buildImport("union_tag_as_int")(p)?.value ?? helpers.readHandle(p)?.value;

const d = (p, depth = 0) => {
  if (!p || depth > 6) return String(p);
  const h = helpers.readHandle(p);
  if (!h) return String(p);
  if (h.tag === 1) return `Int(${h.value})`;
  if (h.tag === 2) return `List(${(h.items || []).length})`;
  if (h.tag === 3) return h.value == null ? "Nothing" : `Just(${d(h.value, depth + 1)})`;
  if (h.tag === 5) return `Closure(${h.fnIndex},arity=${h.arity})`;
  if (h.tag === 6) return `T2(${d(h.first, depth + 1)}, ${d(h.second, depth + 1)})`;
  if (h.tag === 7) return `Str(${JSON.stringify(h.value?.slice?.(0, 60) ?? h.value)})`;
  if (h.tag === 8) return h.isOk ? `Ok(${d(h.value, depth + 1)})` : `Err(${d(h.value, depth + 1)})`;
  if (h.tag === 11) {
    return `Rec(${h.fields.map((f, i) => `f${i}=${d(f, depth + 1)}`).join(", ")})`;
  }
  return `tag${h.tag}(${p})`;
};

const invokeClosure = (fnPtr, args) => {
  const payload = helpers.readHandle(fnPtr);
  if (payload?.tag !== 5) return { rc: 1, value: 0 };
  const entry = manifest.closures[payload.fnIndex];
  const exportFn = instance.exports[entry.export];
  const result = exportFn(...(payload.captures || []), ...args);
  return { rc: result[0], value: result[1] };
};

const html = readFileSync(join(repoRoot, "elm_pebble_dev/dist/index.html"), "utf8");
const pageBytes = Buffer.from(html.match(/id="__ELM_PAGES_BYTES_DATA__"[^>]*>([^<]+)</)[1], "base64");
console.log("page bytes", [...pageBytes]);

const { value: programHandle } = callExport("elmc_fn_Main_main", []);
const bytesHandle = helpers.newBytesFromUint8Array(new Uint8Array(pageBytes));

const boot = helpers.bootBrowserProgram(programHandle, {
  incomingPorts: { pageDataFromJs: bytesHandle },
});

const model = helpers.readHandle(boot.modelPtr);
console.log("\nPlatform model after port:");
console.log("  pageData", d(model.fields[4]));
console.log("  notFound", d(model.fields[5]));
console.log("  pendingFrozenViewsUrl", d(model.fields[13]));
console.log("  url.path", d(helpers.readHandle(model.fields[1])?.fields?.[3]));

const pd = helpers.readHandle(model.fields[4]);
if (pd?.isOk) {
  const payload = helpers.readHandle(pd.value);
  console.log("\npageData Ok payload:");
  console.log("  userModel", d(payload?.fields?.[0]));
  console.log("  pageData union tag", unionTag(payload?.fields?.[1]));
  console.log("  pageData", d(payload?.fields?.[1]));
  console.log("  sharedData", d(payload?.fields?.[2]));
  console.log("  actionData", d(payload?.fields?.[3]));
}

const program = helpers.readHandle(programHandle);
const impl = helpers.readHandle(program.impl);
const initFn = impl.fields[0];
const config = helpers.readHandle(initFn)?.captures?.[0];
const configRec = helpers.readHandle(config);

const decodeResponse = callExport("elmc_fn_Main_decodeResponse", []);
const scratch = 9000;
helpers.buildImport("bytes_cmd")(scratch, 5, decodeResponse.value, bytesHandle);
const readOut = (p) => new DataView(memory.buffer).getUint32(p, true);
const decoded = helpers.readHandle(readOut(scratch));
console.log("\ndecodeResponse result:", d(decoded));
if (decoded?.value != null) {
  console.log("  sketch tag", unionTag(decoded.value));
  console.log("  sketch", d(decoded.value));
  const sketch = helpers.readHandle(decoded.value);
  if (sketch?.tag === 6) {
    const list = helpers.readHandle(sketch.second);
    (list?.items || []).forEach((it, i) =>
      console.log(`  list[${i}] tag=${unionTag(it)}`, d(it))
    );
  }
}

const mv = callExport("elmc_fn_Pages_Internal_Platform_mainView", [config, boot.modelPtr]);
console.log("\nmainView", mv.rc, d(mv.value));

// Build page {path, route} like mainView: urlToRoute on model url
const url = model.fields[1];
const urlToRoute = configRec.fields[22]; // guess - scan for closure
let urlToRouteFn = null;
for (let i = 0; i < (configRec.fields?.length ?? 0); i++) {
  const h = helpers.readHandle(configRec.fields[i]);
  if (h?.tag === 5) {
    const entry = manifest.closures[h.fnIndex];
    if (entry?.export?.includes("urlToRoute")) {
      urlToRouteFn = configRec.fields[i];
      console.log("urlToRoute at field", i, entry.export);
    }
  }
}
if (urlToRouteFn) {
  const routeRes = invokeClosure(urlToRouteFn, [url]);
  console.log("urlToRoute result tag", unionTag(routeRes.value), d(routeRes.value));
}

// Main.view with pageData union from payload
if (pd?.isOk) {
  const payload = helpers.readHandle(pd.value);
  const pageDataUnion = payload?.fields?.[1];
  const pageFormState = model.fields[11];
  const fetchers = model.fields[10];
  const transition = model.fields[8];
  const sharedData = payload?.fields?.[2];
  const actionData = payload?.fields?.[3];

  // Minimal page record - path from currentPath, route from urlToRoute  
  const pathStr = model.fields[2];
  const route = urlToRouteFn ? invokeClosure(urlToRouteFn, [url]).value : 0;
  const pageRec = callExport("runtime_record_new", [pathStr, route, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]).value;

  const mainViewFn = callExport("elmc_fn_Main_view", [
    pageFormState,
    fetchers,
    transition,
    pageRec,
    0, // maybePageUrl
    sharedData,
    pageDataUnion,
    actionData,
  ]);
  console.log("\nMain.view (8-arg)", mainViewFn.rc, d(mainViewFn.value));
  if (mainViewFn.value) {
    const app = helpers.readHandle(mainViewFn.value);
    console.log("  App.view field", d(app?.fields?.[0]));
    if (app?.fields?.[0]) {
      const viewRes = invokeClosure(app.fields[0], [payload?.fields?.[0] ?? 0]);
      console.log("  App.view(userModel)", d(viewRes.value));
    }
  }
}
