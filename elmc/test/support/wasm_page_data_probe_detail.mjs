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
    closureCount: manifest.closure_count ?? null,
    closureCount: manifest.closure_count ?? null,
  immortalStrings: manifest.immortal_strings || {},
});

const unionTag = (p) => {
  try {
    return helpers.buildImport("union_tag_as_int")(p);
  } catch {
    return helpers.readHandle(p)?.value;
  }
};

const d = (p, depth = 0) => {
  if (!p || depth > 5) return String(p);
  const h = helpers.readHandle(p);
  if (!h) return String(p);
  if (h.tag === 1) return `Int(${h.value})`;
  if (h.tag === 2) return `List(${h.items?.length ?? 0})`;
  if (h.tag === 3) return h.value == null ? "Nothing" : `Just(${d(h.value, depth + 1)})`;
  if (h.tag === 5) return `Closure(${h.fnIndex})`;
  if (h.tag === 6) return `T2(${d(h.first, depth + 1)}, ${d(h.second, depth + 1)})`;
  if (h.tag === 7) return `Str(${JSON.stringify(h.value?.slice?.(0, 50) ?? h.value)})`;
  if (h.tag === 8) return h.isOk ? `Ok(${d(h.value, depth + 1)})` : `Err(${d(h.value, depth + 1)})`;
  if (h.tag === 11) return `Rec(n=${h.fields.length}, ${h.fields.map((f, i) => `${i}:${d(f, depth + 1)}`).join(", ")})`;
  return `tag${h.tag}(${p})`;
};

const invokeClosure = (fnPtr, args) => {
  const payload = helpers.readHandle(fnPtr);
  if (payload?.tag !== 5) return { rc: 1, value: 0 };
  const entry = manifest.closures[payload.fnIndex];
  const result = instance.exports[entry.export](...(payload.captures || []), ...args);
  return { rc: result[0], value: result[1] };
};

const html = readFileSync(join(repoRoot, "elm_pebble_dev/dist/index.html"), "utf8");
const pageBytes = Buffer.from(html.match(/id="__ELM_PAGES_BYTES__"[^>]*>([^<]+)</)?.[1] ?? html.match(/id="__ELM_PAGES_BYTES_DATA__"[^>]*>([^<]+)</)[1], "base64");
console.log("bytes", [...pageBytes]);

const { value: programHandle } = callExport("elmc_fn_Main_main", []);
const bytesHandle = helpers.newBytesFromUint8Array(new Uint8Array(pageBytes));
const boot = helpers.bootBrowserProgram(programHandle, {
  incomingPorts: { pageDataFromJs: bytesHandle },
});

const model = helpers.readHandle(boot.modelPtr);
console.log("\nPlatform model fields:");
for (let i = 0; i < (model?.fields?.length ?? 0); i++) {
  console.log(`  [${i}]`, d(model.fields[i]));
}

const pd = helpers.readHandle(model.fields[4]);
if (pd?.isOk) {
  const inner = helpers.readHandle(pd.value);
  console.log("\npageData Ok inner:");
  console.log("  userModel [0]", d(inner?.fields?.[0]));
  console.log("  pageData  [1] tag", unionTag(inner?.fields?.[1]), d(inner?.fields?.[1]));
  console.log("  shared    [2]", d(inner?.fields?.[2]));
  console.log("  action    [3]", d(inner?.fields?.[3]));
}

const program = helpers.readHandle(programHandle);
const config = helpers.readHandle(helpers.readHandle(program.impl).fields[0])?.captures?.[0];

const mv = callExport("elmc_fn_Pages_Internal_Platform_mainView", [config, boot.modelPtr]);
console.log("\nmainView", mv.rc, d(mv.value));

if (pd?.isOk) {
  const userModel = helpers.readHandle(pd.value)?.fields?.[0];
  const pageDataUnion = helpers.readHandle(pd.value)?.fields?.[1];

  // Main.view needs pageData union + page record - call with minimal reconstruction
  const url = model.fields[1];
  const cfg = helpers.readHandle(config);
  let urlToRouteFn = null;
  for (const f of cfg.fields ?? []) {
    const h = helpers.readHandle(f);
    if (h?.tag === 5) {
      const exp = manifest.closures[h.fnIndex]?.export ?? "";
      if (exp.includes("urlToRoute")) urlToRouteFn = f;
    }
  }
  const route = urlToRouteFn ? invokeClosure(urlToRouteFn, [url]).value : 0;
  console.log("\nroute from urlToRoute tag", unionTag(route), d(route));

  const pathStr = model.fields[2];
  const pageRec = callExport("elmc_fn_Main_view", [
    model.fields[11],
    model.fields[10],
    model.fields[8],
    callExport("elmc_fn_UrlPath_join", [pathStr]).value, // wrong shape - skip
  ]);
}

// Direct Main.view via export with zeros to see if case works when given DataIndex manually
const dataIndexTag = 13; // IR constructor tag for DataIndex
const unit = callExport("elmc_fn_Elm_Kernel_Utils_unit", [])?.value ?? 0;
const dataIndex = helpers.buildImport("tuple2")(dataIndexTag, unit); // probably wrong API

console.log("\nboot title:", JSON.stringify(boot.title));
console.log("boot view:", d(boot.value));
