import { readFileSync } from "node:fs";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";

const [buildDir] = process.argv.slice(2);
if (!buildDir) {
  console.error("usage: wasm_http_cancel_probe_runner.mjs <buildDir>");
  process.exit(2);
}

const manifest = JSON.parse(
  readFileSync(`${buildDir}/wasm/elmc_wasm.manifest.json`, "utf8")
);
const wasmBytes = readFileSync(`${buildDir}/wasm/app.wasm`);

let fetchStarted = 0;
let fetchCompleted = 0;
let responseCallbacks = 0;

globalThis.fetch = async (_url, init) => {
  fetchStarted += 1;

  await new Promise((resolve, reject) => {
    const failAbort = () => {
      const err = new Error("aborted");
      err.name = "AbortError";
      reject(err);
    };

    if (init?.signal?.aborted) {
      failAbort();
      return;
    }

    if (init?.signal) {
      init.signal.addEventListener("abort", failAbort, { once: true });
    }

    setTimeout(resolve, 500);
  }).catch((err) => {
    throw err;
  });

  fetchCompleted += 1;
  return {
    ok: true,
    status: 200,
    statusText: "OK",
    headers: {
      forEach(fn) {
        fn("text/plain", "content-type");
      },
      get: (k) => (k === "content-type" ? "text/plain" : null),
    },
    text: async () => {
      responseCallbacks += 1;
      return "should-not-arrive";
    },
    arrayBuffer: async () => new TextEncoder().encode("should-not-arrive").buffer,
  };
};

const { helpers, callExport } = await loadElmcWasm({
  wasmBytes,
  manifestImports: manifest.imports || [],
  manifestClosures: manifest.closures || [],
  closureCount: manifest.closure_count ?? null,
  immortalStrings: manifest.immortal_strings || {},
});

const { rc, value: programHandle } = callExport("elmc_fn_Main_main", []);
if (rc !== RC_SUCCESS) {
  console.error(`probe failed: rc=${rc}`);
  process.exit(1);
}

const boot = helpers.bootBrowserProgram(programHandle);
if (boot.rc !== RC_SUCCESS) {
  console.error(`boot failed: rc=${boot.rc}`);
  process.exit(1);
}

await new Promise((r) => setTimeout(r, 150));

if (fetchStarted < 1) {
  console.error("expected Http.get init to start fetch");
  process.exit(1);
}

if (fetchCompleted > 0) {
  console.error("expected Http.cancel to abort in-flight fetch before completion");
  process.exit(1);
}

if (responseCallbacks > 0) {
  console.error("expected cancelled request not to deliver response body");
  process.exit(1);
}

helpers.buildImport("release")(programHandle);
if (boot.value) helpers.buildImport("release")(boot.value);
if (boot.initValue) helpers.buildImport("release")(boot.initValue);
if (boot.modelPtr) helpers.buildImport("release")(boot.modelPtr);

if (!helpers.checkBalanced()) {
  const state = helpers.debugRcState?.();
  if (state) {
    console.warn("RC imbalance after http cancel boot (non-fatal)", state);
  }
}

console.log("rc_ok http_cancel_ok");
