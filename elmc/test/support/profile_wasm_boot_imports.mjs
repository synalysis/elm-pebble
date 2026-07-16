import { readFileSync } from "fs";
import { spawnSync } from "child_process";
import { createRcRuntime, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/rc_runtime.js";
import { decodePageBytesFromHtml } from "../../../elmc-wasm-runtime/host/page_bytes.js";

const root = process.argv[2] || "elm_pebble_dev/dist/wasm-web";
const manifest = JSON.parse(readFileSync(`${root}/wasm/elmc_wasm.manifest.json`, "utf8"));
const wasmBytes = new Uint8Array(readFileSync(`${root}/wasm/app.wasm`));
const pageBytes = decodePageBytesFromHtml(readFileSync("elm_pebble_dev/dist/index.html", "utf8"));

const counts = Object.create(null);
const times = Object.create(null);
let active = false;

function wrapFn(name, fn) {
  return (...args) => {
    if (!active) return fn(...args);
    const t0 = performance.now();
    try {
      return fn(...args);
    } finally {
      counts[name] = (counts[name] || 0) + 1;
      times[name] = (times[name] || 0) + (performance.now() - t0);
    }
  };
}

const runtimeApi = createRcRuntime({ immortalStrings: manifest.immortal_strings || {} });
const module = await WebAssembly.compile(wasmBytes);
const importNames = WebAssembly.Module.imports(module)
  .filter((e) => e.module === "runtime" && e.kind === "function")
  .map((e) => e.name);

const runtime = {
  retain: wrapFn("retain", runtimeApi.buildImport("retain")),
  release: wrapFn("release", runtimeApi.buildImport("release")),
  release_array_lifo: wrapFn("release_array_lifo", runtimeApi.buildImport("release_array_lifo")),
};
for (const name of importNames) {
  if (!(name in runtime)) runtime[name] = wrapFn(name, runtimeApi.buildImport(name));
}

const instance = await WebAssembly.instantiate(module, { runtime });
runtimeApi.setMemory(instance.exports.memory);
runtimeApi.setClosureInvoker((fnIndex, captures, callArgs) => {
  const entry = Array.isArray(manifest.closures) ? manifest.closures[fnIndex] : null;
  const name = typeof entry === "string" ? entry : (entry?.export ?? `c${fnIndex}`);
  const fn = instance.exports[name];
  if (typeof fn !== "function") return { rc: 0, value: 0 };
  const args = [...captures, ...callArgs];
  runtimeApi.pushCallRoots(args);
  try {
    const result = fn(...args);
    if (Array.isArray(result)) return { rc: result[0] | 0, value: result[1] | 0 };
    return { rc: 0, value: result | 0 };
  } finally {
    runtimeApi.popCallRoots();
  }
});

function callExport(name, args = []) {
  const fn = instance.exports[name];
  runtimeApi.pushCallRoots(args);
  try {
    const result = fn(...args);
    if (Array.isArray(result)) return { rc: result[0], value: result[1] };
    return { rc: result, value: 0 };
  } finally {
    runtimeApi.popCallRoots();
  }
}

const { rc, value } = callExport(manifest.entry_export || "elmc_fn_Main_main", []);
if (rc !== RC_SUCCESS) throw new Error(`main rc=${rc}`);
const bytesHandle = runtimeApi.newBytesFromUint8Array(pageBytes);

for (const k of Object.keys(counts)) delete counts[k];
for (const k of Object.keys(times)) delete times[k];
active = true;
const boot = runtimeApi.bootBrowserProgram(value, {
  incomingPorts: { pageDataFromJs: bytesHandle },
  skipInnerText: true,
  omitPortRcWalk: true,
});
active = false;

const top = Object.keys(times)
  .map((k) => ({ name: k, ms: +times[k].toFixed(2), n: counts[k] | 0 }))
  .sort((a, b) => b.ms - a.ms)
  .slice(0, 12);

console.log(JSON.stringify({
  title: boot.title,
  phases: boot.phases,
  reachCache: runtimeApi.reachCacheStats?.() ?? null,
  top,
  reach_ms: +(times.release_unless_reachable_from_roots || 0).toFixed(2),
  reach_n: counts.release_unless_reachable_from_roots || 0,
}, null, 2));

const probe = spawnSync(
  "node",
  ["elmc/test/support/wasm_browser_page_data_probe_runner.mjs", root],
  { encoding: "utf8" }
);
console.log(probe.stdout.trim());
console.log("probe", probe.status);
