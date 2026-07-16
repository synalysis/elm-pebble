#!/usr/bin/env node
/**
 * Node boot microbench for an elmc wasm-web out dir.
 * Usage: node benchmark_wasm_boot.mjs <out-dir> [page.html]
 */
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
import { performance } from "node:perf_hooks";
import { resolve, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "../../..");
const outDir = resolve(process.argv[2] || join(repoRoot, "elm_pebble_dev/dist/wasm-web"));
const pageHtmlPath = process.argv[3]
  ? resolve(process.argv[3])
  : join(repoRoot, "elm_pebble_dev/dist/index.html");

const { loadElmcWasm } = await import(
  pathToFileURL(join(repoRoot, "elmc-wasm-runtime/host/loader.js")).href
);
const { decodePageBytesFromHtml } = await import(
  pathToFileURL(join(repoRoot, "elmc-wasm-runtime/host/page_bytes.js")).href
);

const manifest = JSON.parse(readFileSync(join(outDir, "wasm/elmc_wasm.manifest.json"), "utf8"));
const wasmBytes = readFileSync(join(outDir, "wasm/app.wasm"));
let pageBytes = null;
try {
  pageBytes = decodePageBytesFromHtml(readFileSync(pageHtmlPath, "utf8"));
} catch {
  pageBytes = null;
}

const runs = [];
for (let i = 0; i < 5; i++) {
  const t0 = performance.now();
  const { helpers, callExport } = await loadElmcWasm({
    wasmBytes,
    manifestImports: manifest.imports || [],
    manifestClosures: manifest.closures || [],
    closureCount: manifest.closure_count ?? null,
    immortalStrings: manifest.immortal_strings || {},
  });
  const t1 = performance.now();
  const { rc, value } = callExport(manifest.entry_export || "elmc_fn_Main_main", []);
  const t2 = performance.now();
  let boot = { rc, title: null, innerText: "" };
  if (helpers.isBrowserProgram(value)) {
    const opts = pageBytes
      ? { incomingPorts: { pageDataFromJs: helpers.newBytesFromUint8Array(pageBytes) } }
      : {};
    boot = helpers.bootBrowserProgram(value, opts);
  }
  const t3 = performance.now();
  runs.push({
    instantiate_ms: t1 - t0,
    main_ms: t2 - t1,
    boot_ms: t3 - t2,
    total_ms: t3 - t0,
    rc,
    boot_rc: boot.rc,
    title: boot.title,
    text_len: (boot.innerText || "").length,
  });
}

const avg = (key) => runs.reduce((s, r) => s + r[key], 0) / runs.length;

console.log("=== boot timings (node, n=5) ===");
console.log(
  JSON.stringify(
    {
      instantiate_ms: +avg("instantiate_ms").toFixed(1),
      main_ms: +avg("main_ms").toFixed(1),
      boot_ms: +avg("boot_ms").toFixed(1),
      total_ms: +avg("total_ms").toFixed(1),
      title: runs[0].title,
      text_len: runs[0].text_len,
    },
    null,
    2
  )
);
