import { readFileSync } from "node:fs";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";

const [buildDir, exportName, expectedChecksum] = process.argv.slice(2);

if (!buildDir || !exportName) {
  console.error("usage: wasm_probe_runner.mjs <buildDir> <exportName> [expectedChecksum]");
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

const { rc, value: resultHandle } = callExport(exportName, []);

if (rc !== RC_SUCCESS) {
  console.error(`probe failed: rc=${rc}`);
  process.exit(1);
}

const checksum = helpers.unboxInt(resultHandle);
helpers.buildImport("release")(resultHandle);

if (!helpers.checkBalanced()) {
  console.error("rc leak detected after probe");
  process.exit(1);
}

if (expectedChecksum !== undefined) {
  const expected = Number(expectedChecksum);
  if (checksum !== expected) {
    console.error(`checksum mismatch: got ${checksum}, expected ${expected}`);
    process.exit(1);
  }
}

console.log(`rc_ok probe ${exportName} checksum=${checksum}`);
