import { readFileSync } from "node:fs";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";

const [buildDir] = process.argv.slice(2);

if (!buildDir) {
  console.error("usage: wasm_port_incoming_probe_runner.mjs <buildDir>");
  process.exit(2);
}

const manifest = JSON.parse(
  readFileSync(`${buildDir}/wasm/elmc_wasm.manifest.json`, "utf8")
);

const wasmBytes = readFileSync(`${buildDir}/wasm/app.wasm`);

const { helpers, callExport, memory } = await loadElmcWasm({
  wasmBytes,
  manifestImports: manifest.imports || [],
  manifestClosures: manifest.closures || [],
  immortalStrings: manifest.immortal_strings || {},
});

const { rc, value: programHandle } = callExport("elmc_fn_Main_main", []);

if (rc !== RC_SUCCESS) {
  console.error(`probe failed: rc=${rc}`);
  process.exit(1);
}

if (!helpers.isBrowserProgram(programHandle)) {
  console.error("probe failed: export did not return a browser program handle");
  process.exit(1);
}

const scratch = 8192;
helpers.buildImport("new_int")(scratch, 42);
const payload = new DataView(memory.buffer).getUint32(scratch, true);

const boot = helpers.bootBrowserProgram(programHandle, {
  incomingPorts: { listen: payload },
});

if (boot.rc !== RC_SUCCESS) {
  console.error(`browser boot failed: rc=${boot.rc} stage=${boot.stage ?? "unknown"}`);
  process.exit(1);
}

if (boot.innerText !== "42") {
  console.error(
    `innerText mismatch: got ${JSON.stringify(boot.innerText)}, expected ${JSON.stringify("42")}`
  );
  process.exit(1);
}

console.log("rc_ok incoming_port_ok");
