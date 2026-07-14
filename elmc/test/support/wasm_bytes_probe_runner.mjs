import { readFileSync } from "node:fs";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";

const [buildDir, exportName, byteValue, expectedText] = process.argv.slice(2);

if (!buildDir || !exportName || byteValue === undefined) {
  console.error(
    "usage: wasm_bytes_probe_runner.mjs <buildDir> <exportName> <byteValue> [expectedText]"
  );
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
  immortalStrings: manifest.immortal_strings || {},
});

const bytesHandle = helpers.bytesFromList([Number(byteValue) & 0xff]);
if (!bytesHandle) {
  console.error("probe failed: could not build bytes handle");
  process.exit(1);
}

const { rc, value: resultHandle } = callExport(exportName, [bytesHandle]);

if (rc !== RC_SUCCESS) {
  console.error(`probe failed: rc=${rc}`);
  process.exit(1);
}

const vdom = helpers.inspectVdom(resultHandle);

if (!vdom) {
  console.error("probe failed: export did not return a vdom handle");
  process.exit(1);
}

helpers.buildImport("release")(resultHandle);
helpers.buildImport("release")(bytesHandle);

if (!helpers.checkBalanced()) {
  console.error("rc leak detected after probe");
  process.exit(1);
}

const text = vdom.kind === "text" ? vdom.text : vdom.innerText;
const expected = expectedText ?? `byte:${byteValue}`;

if (text !== expected) {
  console.error(`vdom text mismatch: got ${JSON.stringify(text)}, expected ${JSON.stringify(expected)}`);
  process.exit(1);
}

console.log(`rc_ok vdom_text=${text}`);
