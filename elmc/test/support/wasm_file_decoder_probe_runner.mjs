import { readFileSync } from "node:fs";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";

const [buildDir] = process.argv.slice(2);

if (!buildDir) {
  console.error("usage: wasm_file_decoder_probe_runner.mjs <buildDir>");
  process.exit(2);
}

if (typeof File === "undefined") {
  console.error("File constructor is not available");
  process.exit(2);
}

const manifest = JSON.parse(
  readFileSync(`${buildDir}/wasm/elmc_wasm.manifest.json`, "utf8")
);

let wasmBytes;
try {
  wasmBytes = readFileSync(`${buildDir}/wasm/app.wasm`);
} catch (_err) {
  wasmBytes = readFileSync(`${buildDir}/wasm/elmc_generated.wasm`);
}

const { helpers, callExport } = await loadElmcWasm({
  wasmBytes,
  manifestImports: manifest.imports || [],
  manifestClosures: manifest.closures || [],
  closureCount: manifest.closure_count ?? null,
  immortalStrings: manifest.immortal_strings || {},
  constructorTags: manifest.constructor_tags || {},
});

const file = new File(["hi"], "notes.md", { type: "text/markdown" });
const expected = `${file.name},${file.type},${file.size},${file.lastModified | 0}`;
const files =
  typeof FileList !== "undefined"
    ? Object.assign(Object.create(FileList.prototype), {
        0: file,
        length: 1,
        item(i) {
          return i === 0 ? file : null;
        },
      })
    : [file];

const valueHandle = helpers.jsonValueFromJs({ files });
const { rc, value: resultHandle } = callExport("elmc_fn_Main_main", [valueHandle]);

if (rc !== RC_SUCCESS) {
  console.error(`probe failed: rc=${rc}`);
  process.exit(1);
}

const vdom = helpers.inspectVdom(resultHandle);
const text = vdom?.kind === "text" ? vdom.text : vdom?.innerText;
if (text !== expected) {
  console.error(`expected ${expected}, got ${JSON.stringify(vdom)}`);
  process.exit(1);
}

helpers.buildImport("release")(resultHandle);
helpers.buildImport("release")(valueHandle);

console.log("rc_ok file_decoder_ok");
