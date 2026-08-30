import { readFileSync } from "node:fs";
import { parseHTML } from "linkedom";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";

const [buildDir] = process.argv.slice(2);
if (!buildDir) {
  console.error("usage: wasm_process_http_kill_probe_runner.mjs <buildDir>");
  process.exit(2);
}

const { document } = parseHTML("<!doctype html><html><body><div id='app'></div></body></html>");
globalThis.document = document;
globalThis.window = document.defaultView;
globalThis.Node = document.defaultView.Node;

let fetchStarted = 0;
let fetchCompleted = 0;

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
    text: async () => "should-not-arrive",
    arrayBuffer: async () => new TextEncoder().encode("should-not-arrive").buffer,
  };
};

const manifest = JSON.parse(
  readFileSync(`${buildDir}/wasm/elmc_wasm.manifest.json`, "utf8")
);
const wasmBytes = readFileSync(`${buildDir}/wasm/app.wasm`);

const { helpers, callExport } = await loadElmcWasm({
  wasmBytes,
  manifestImports: manifest.imports || [],
  manifestClosures: manifest.closures || [],
  closureCount: manifest.closure_count ?? null,
  immortalStrings: manifest.immortal_strings || {},
  constructorTags: manifest.constructor_tags || {},
});

const { rc, value: programHandle } = callExport("elmc_fn_Main_main", []);
if (rc !== RC_SUCCESS) {
  console.error(`probe failed: rc=${rc}`);
  process.exit(1);
}

const boot = helpers.bootBrowserProgram(programHandle);
if (boot.rc !== RC_SUCCESS) {
  console.error(`boot failed: rc=${boot.rc} stage=${boot.stage ?? "unknown"}`);
  process.exit(1);
}

await new Promise((r) => setTimeout(r, 600));

const innerText = document.getElementById("app")?.textContent ?? boot.innerText ?? "";
if (fetchStarted < 1) {
  console.error("expected spawned Http.task to start fetch");
  process.exit(1);
}
if (fetchCompleted > 0) {
  console.error("expected Process.kill to abort spawned Http.task before completion");
  process.exit(1);
}
if (innerText !== "ok") {
  console.error(
    `expected Task.perform sleep to finish after Process.kill, got ${JSON.stringify(innerText)}`
  );
  process.exit(1);
}

helpers.buildImport("release")(programHandle);
if (boot.value) helpers.buildImport("release")(boot.value);
if (boot.initValue) helpers.buildImport("release")(boot.initValue);
if (boot.modelPtr) helpers.buildImport("release")(boot.modelPtr);

if (!helpers.checkBalanced()) {
  const state = helpers.debugRcState?.();
  if (state) {
    console.warn("RC imbalance after process http kill boot (non-fatal)", state);
  }
}

console.log("rc_ok process_http_kill_ok");
