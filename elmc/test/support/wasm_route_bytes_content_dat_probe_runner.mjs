/**
 * Unit probe: route_bytes prefers content.dat and can resolve every all-paths entry.
 *
 * usage: node elmc/test/support/wasm_route_bytes_content_dat_probe_runner.mjs <distDir>
 */
import { readFileSync, existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { createRouteBytesRuntime } from "../../../elmc-wasm-runtime/host/route_bytes.js";

const distDir = resolve(process.argv[2] || "elm_pebble_dev/dist");
const allPathsFile = join(distDir, "all-paths.json");
const indexHtml = join(distDir, "index.html");

if (!existsSync(allPathsFile) || !existsSync(indexHtml)) {
  console.error(`missing all-paths.json or index.html under ${distDir}`);
  process.exit(2);
}

const paths = JSON.parse(readFileSync(allPathsFile, "utf8")).filter(
  (p) => typeof p === "string" && !p.endsWith(".json")
);
if (!Array.isArray(paths) || paths.length === 0) {
  console.error("all-paths.json has no page routes");
  process.exit(1);
}

const runtime = createRouteBytesRuntime({
  fetchFn: async (url) => {
    const u = new URL(url);
    // file:// URLs from pathToFileURL
    const filePath = decodeURIComponent(u.pathname);
    if (!existsSync(filePath)) {
      return { ok: false, status: 404, arrayBuffer: async () => new ArrayBuffer(0), text: async () => "" };
    }
    const buf = readFileSync(filePath);
    return {
      ok: true,
      status: 200,
      arrayBuffer: async () => buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength),
      text: async () => buf.toString("utf8"),
    };
  },
});

runtime.setSiteRootFromPageHtml(pathToFileURL(indexHtml).href);
runtime.setRuntimeFetcher(runtime.defaultRuntimeFetcher);

const missing = [];
const empty = [];
for (const path of paths) {
  const bytes = await runtime.lookup(path);
  if (!bytes) {
    missing.push(path);
    continue;
  }
  if (bytes.byteLength === 0) empty.push(path);
}

if (missing.length || empty.length) {
  console.error(
    `route bytes probe failed: missing=${missing.length} empty=${empty.length}`
  );
  if (missing.length) console.error("missing:", missing.slice(0, 20).join(", "));
  if (empty.length) console.error("empty:", empty.slice(0, 20).join(", "));
  process.exit(1);
}

console.log(
  `rc_ok route_bytes_content_dat routes=${paths.length} sample=${paths.slice(0, 5).join(",")}`
);
