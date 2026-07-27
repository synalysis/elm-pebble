/**
 * Ensure deep-link site root does not prefix later content.dat fetches.
 *
 * usage: node elmc/test/support/wasm_route_bytes_site_root_probe_runner.mjs
 */
import { createRouteBytesRuntime } from "../../../elmc-wasm-runtime/host/route_bytes.js";

const fetched = [];
const runtime = createRouteBytesRuntime({
  fetchFn: async (url) => {
    fetched.push(url);
    return {
      ok: true,
      status: 200,
      arrayBuffer: async () => new Uint8Array([1, 2, 3]).buffer,
      text: async () => "",
    };
  },
});

// Simulate SPA deep-link boot of /getting-started, then nav to /f-a-q.
runtime.setSiteRootFromPageHtml("http://localhost:8080/getting-started/index.html");
runtime.setRuntimeFetcher(runtime.defaultRuntimeFetcher);

const bytes = await runtime.lookup("/f-a-q");
if (!bytes || bytes.byteLength !== 3) {
  console.error("lookup failed", { bytes, fetched });
  process.exit(1);
}

const bad = fetched.find((u) => u.includes("/getting-started/f-a-q/"));
const good = fetched.find((u) => u === "http://localhost:8080/f-a-q/content.dat");
if (bad || !good) {
  console.error("site root still wrong", { fetched, bad, good });
  process.exit(1);
}

fetched.length = 0;
runtime.setSiteRootFromPageHtml("http://localhost:8080/wasm-web/host/browser.html");
await runtime.lookup("/wasm");
const wasmUrl = fetched.find((u) => u.endsWith("/wasm/content.dat"));
if (wasmUrl !== "http://localhost:8080/wasm/content.dat") {
  console.error("host shell site root wrong", { fetched, wasmUrl });
  process.exit(1);
}

console.log("rc_ok route_bytes_site_root");
