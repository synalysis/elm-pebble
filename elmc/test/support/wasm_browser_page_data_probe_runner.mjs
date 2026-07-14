import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "../../..");

const [buildDir, bytesSource] = process.argv.slice(2);

if (!buildDir) {
  console.error(
    "usage: wasm_browser_page_data_probe_runner.mjs <buildDir> [base64|path-to-bytes]"
  );
  process.exit(2);
}

const manifest = JSON.parse(
  readFileSync(`${buildDir}/wasm/elmc_wasm.manifest.json`, "utf8")
);

const wasmBytes = readFileSync(`${buildDir}/wasm/app.wasm`);

const { helpers, callExport } = await loadElmcWasm({
  wasmBytes,
  manifestImports: manifest.imports || [],
  manifestClosures: manifest.closures || [],
  immortalStrings: manifest.immortal_strings || {},
});

let pageBytesSource;

if (!bytesSource) {
  const htmlPath =
    process.env.ELM_PAGES_INDEX_HTML ??
    join(repoRoot, "elm_pebble_dev/dist/index.html");
  const html = readFileSync(htmlPath, "utf8");
  const match = html.match(/id="__ELM_PAGES_BYTES_DATA__"[^>]*>([^<]+)</);
  if (!match) {
    console.error("probe failed: could not find __ELM_PAGES_BYTES_DATA__ in index.html");
    process.exit(1);
  }
  pageBytesSource = Buffer.from(match[1], "base64");
} else if (/^[A-Za-z0-9+/=]+$/.test(bytesSource) && bytesSource.length <= 256) {
  pageBytesSource = Buffer.from(bytesSource, "base64");
} else {
  pageBytesSource = readFileSync(bytesSource);
}

const { rc, value: programHandle } = callExport("elmc_fn_Main_main", []);

if (rc !== RC_SUCCESS) {
  console.error(`probe failed: rc=${rc}`);
  process.exit(1);
}

// Allocate page bytes after main so init epilogue cannot release the handle.
const bytesHandle = helpers.newBytesFromUint8Array(new Uint8Array(pageBytesSource));

const boot = helpers.bootBrowserProgram(programHandle, {
  incomingPorts: { pageDataFromJs: bytesHandle },
});

if (boot.rc !== RC_SUCCESS) {
  console.error(`browser boot failed: rc=${boot.rc} stage=${boot.stage ?? "unknown"}`);
  process.exit(1);
}

if (boot.title === "Page Data Error") {
  console.error(`title still error page: ${JSON.stringify(boot.title)}`);
  process.exit(1);
}

if (!boot.title) {
  console.error("title missing after pageDataFromJs");
  process.exit(1);
}

console.log(
  `rc_ok page_data_title=${JSON.stringify(boot.title)} innerText=${JSON.stringify(boot.innerText?.slice(0, 120) ?? "")}`
);
