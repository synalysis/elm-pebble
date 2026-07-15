import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { loadElmcWasm } from "../../../elmc-wasm-runtime/host/loader.js";

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "../../..");
const buildDir = process.argv[2] ?? "/tmp/elm_pebble_dev_wasm";
const manifest = JSON.parse(readFileSync(`${buildDir}/wasm/elmc_wasm.manifest.json`, "utf8"));
const wasmBytes = readFileSync(`${buildDir}/wasm/app.wasm`);
const { helpers, callExport, instance } = await loadElmcWasm({
  wasmBytes,
  manifestImports: manifest.imports || [],
  manifestClosures: manifest.closures || [],
  immortalStrings: manifest.immortal_strings || {},
});

const invokeClosure = (fnPtr, args) => {
  const payload = helpers.readHandle(fnPtr);
  if (payload?.tag !== 5) return { rc: 1, value: 0 };
  const entry = manifest.closures[payload.fnIndex];
  const result = instance.exports[entry.export](...(payload.captures || []), ...args);
  return { rc: result[0], value: result[1] };
};

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

const program = helpers.readHandle(programHandle);
const impl = helpers.readHandle(program.impl);
const configRec = helpers.readHandle(impl.fields[1]).captures[0];
const cfg = helpers.readHandle(configRec);
const modelPtr = boot.modelPtr;
const model = helpers.readHandle(modelPtr);
const sketch = helpers.readHandle(helpers.readHandle(model.fields[4]).value);

const reg8 = modelPtr;
const reg11 = configRec;
const reg17 = model.fields[1];
const reg9 = reg17;
const reg12 = cfg.fields[21];
const reg14 = (() => {
  const scratch = 8000;
  helpers.buildImport("retain")(scratch, reg9);
  const url = new DataView(instance.exports.memory.buffer).getUint32(scratch, true);
  helpers.buildImport("retain")(scratch, reg12);
  const key = new DataView(instance.exports.memory.buffer).getUint32(scratch, true);
  helpers.buildImport("record_new")(
    scratch,
    url,
    key,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  );
  return new DataView(instance.exports.memory.buffer).getUint32(scratch, true);
})();

const reg19 = model.fields[10];
const reg20 = model.fields[9];
const reg21 = callExport("elmc_fn_Pages_Internal_Platform_toFetcherState", [reg20]).value;
const reg22 = (() => {
  const scratch = 8012;
  helpers.buildImport("make_closure")(
    scratch,
    544,
    1,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  );
  return new DataView(instance.exports.memory.buffer).getUint32(scratch, true);
})();
const reg23 = model.fields[7];
const reg24 = (() => {
  const scratch = 8024;
  helpers.buildImport("maybe_map")(scratch, reg22, reg23);
  return new DataView(instance.exports.memory.buffer).getUint32(scratch, true);
})();
const reg25 = callExport("elmc_fn_Pages_ContentCache_pathForUrl", []).value;
const reg26 = invokeClosure(reg25, [reg14]).value;
const reg27 = callExport("elmc_fn_UrlPath_join", [reg26]).value;
const reg28 = (() => {
  const scratch = 8036;
  helpers.buildImport("retain")(scratch, reg27);
  return new DataView(instance.exports.memory.buffer).getUint32(scratch, true);
})();
const reg29 = cfg.fields[10];
const reg30 = model.fields[2];
const reg31 = (() => {
  const scratch = 8048;
  helpers.buildImport("retain")(scratch, reg17);
  return new DataView(instance.exports.memory.buffer).getUint32(scratch, true);
})();
const reg32 = (() => {
  const scratch = 8060;
  helpers.buildImport("record_update")(scratch, reg31, reg30, 3);
  return new DataView(instance.exports.memory.buffer).getUint32(scratch, true);
})();
const reg33 = invokeClosure(reg29, [reg32]).value;
const reg34 = (() => {
  const scratch = 8072;
  helpers.buildImport("retain")(scratch, reg33);
  return new DataView(instance.exports.memory.buffer).getUint32(scratch, true);
})();
const reg35 = (() => {
  const scratch = 8084;
  helpers.buildImport("record_new")(
    scratch,
    reg28,
    reg34,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  );
  return new DataView(instance.exports.memory.buffer).getUint32(scratch, true);
})();

// metadata record (reg55) simplified: use maybe_just page path from userModel field 2 inner
const metaJust = helpers.readHandle(sketch.fields[0])?.fields?.[2];
const reg63 = (() => {
  const scratch = 8096;
  helpers.buildImport("maybe_just_own")(scratch, reg35, 1);
  return new DataView(instance.exports.memory.buffer).getUint32(scratch, true);
})();
const reg64 = sketch.fields[2];
const reg65 = sketch.fields[1];
const reg66 = sketch.fields[3];

const mvArgs = [reg19, reg21, reg24, reg35, reg63, reg64, reg65, reg66];
const mainViewResult = callExport("elmc_fn_Main_view", mvArgs);
const reg67 = mainViewResult.value;
const h67 = helpers.readHandle(reg67);
console.log("Main.view full args rc", mainViewResult.rc, "tag", h67?.tag);
if (h67?.tag === 11) {
  const f0 = helpers.readHandle(h67.fields[0]);
  const f1 = helpers.readHandle(h67.fields[1]);
  console.log(" field0", f0?.tag, f0?.fnIndex != null ? manifest.closures[f0.fnIndex]?.export : "");
  console.log(" field1", f1?.tag);
  const viewFn = h67.fields[0];
  const viewPayload = helpers.readHandle(viewFn);
  console.log(
    " view closure",
    viewPayload?.fnIndex,
    manifest.closures[viewPayload?.fnIndex]?.export,
    "captures",
    viewPayload?.captures?.length
  );
  const applied = invokeClosure(viewFn, [sketch.fields[0]]);
  const doc = helpers.readHandle(applied.value);
  console.log(" apply view fn rc", applied.rc, "doc tag", doc?.tag);
  if (doc?.tag === 11) {
    console.log(" title", helpers.readHandle(doc.fields[0])?.value);
  } else if (doc?.tag === 6) {
    console.log(" doc T2 first", helpers.readHandle(doc.first));
    console.log(
      " doc T2 second",
      manifest.closures[helpers.readHandle(doc.second)?.fnIndex]?.export
    );
  }
}

const platformMv = callExport("elmc_fn_Pages_Internal_Platform_mainView", [configRec, modelPtr]);
const pmv = helpers.readHandle(platformMv.value);
console.log("\nPlatform.mainView rc", platformMv.rc, "tag", pmv?.tag);
if (pmv?.tag === 11) {
  console.log(" title slot", helpers.readHandle(pmv.fields[0]));
} else if (pmv?.tag === 6) {
  console.log(" T2 first", helpers.readHandle(pmv.first));
  console.log(" T2 second", manifest.closures[helpers.readHandle(pmv.second)?.fnIndex]?.export);
}
