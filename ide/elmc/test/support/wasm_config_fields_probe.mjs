import { readFileSync } from "node:fs";
import { loadElmcWasm } from "../../../elmc-wasm-runtime/host/loader.js";

const buildDir = process.argv[2] ?? "/tmp/elm_pebble_dev_wasm";
const manifest = JSON.parse(
  readFileSync(`${buildDir}/wasm/elmc_wasm.manifest.json`, "utf8")
);
const wasmBytes = readFileSync(`${buildDir}/wasm/app.wasm`);
const { helpers, callExport } = await loadElmcWasm({
  wasmBytes,
  manifestImports: manifest.imports || [],
  manifestClosures: manifest.closures || [],
    closureCount: manifest.closure_count ?? null,
    closureCount: manifest.closure_count ?? null,
  immortalStrings: manifest.immortal_strings || {},
});

const describe = (p) => {
  const h = helpers.readHandle(p);
  if (!h) return String(p);
  if (h.tag === 1) return `Int(${h.value})`;
  if (h.tag === 5) return `Closure(${h.fnIndex},arity=${h.arity})`;
  if (h.tag === 3) return h.value == null ? "Nothing" : "Just(...)";
  if (h.tag === 11) return `Rec(${h.fields?.length ?? 0})`;
  return `tag${h.tag}(${p})`;
};

const { value: programHandle } = callExport("elmc_fn_Main_main", []);
const program = helpers.readHandle(programHandle);
const initFn = helpers.readHandle(program.impl).fields[0];
const initPayload = helpers.readHandle(initFn);
const config = initPayload.captures[0];
const configRec = helpers.readHandle(config);

console.log("program impl fields", helpers.readHandle(program.impl).fields?.length);
console.log("initFn fnIndex", initPayload.fnIndex, "captures", initPayload.captures?.length);
console.log("config handle", config, "fields", configRec.fields?.length);
for (let i = 0; i < Math.min(8, configRec.fields?.length ?? 0); i++) {
  console.log(`  [${i}]`, describe(configRec.fields[i]));
}

// Compare update capture config
const updateFn = helpers.readHandle(program.impl).fields[2];
const upd = helpers.readHandle(updateFn);
console.log("update fnIndex", upd.fnIndex, "capture0 same as init config?", upd.captures?.[0] === config);
if (upd.captures?.[0] !== config) {
  const updConfig = helpers.readHandle(upd.captures[0]);
  console.log("update config field0", describe(updConfig?.fields?.[0]));
}
