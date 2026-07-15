import { readFileSync } from "node:fs";
import { fileURLToPath, pathToFileURL } from "node:url";
import { bootFromUrls } from "../../../elmc-wasm-runtime/host/boot.js";
import { decodePageBytesFromHtml } from "../../../elmc-wasm-runtime/host/page_bytes.js";

const [buildDirArg, indexHtmlPath, expectedTitle] = process.argv.slice(2);

if (!buildDirArg || !indexHtmlPath) {
  console.error(
    "usage: wasm_browser_boot_probe_runner.mjs <buildDir> <indexHtmlPath> [expectedTitle]"
  );
  process.exit(2);
}

const buildDir = fileURLToPath(pathToFileURL(buildDirArg));
const indexHtml = fileURLToPath(pathToFileURL(indexHtmlPath));
const manifestPath = pathToFileURL(`${buildDir}/wasm/elmc_wasm.manifest.json`).href;
const wasmPath = pathToFileURL(`${buildDir}/wasm/app.wasm`).href;

const fetchFn = (url) => {
  const filePath = url.startsWith("file:") ? fileURLToPath(url) : url;
  const body = readFileSync(filePath);
  return {
    ok: true,
    async json() {
      return JSON.parse(body.toString("utf8"));
    },
    async arrayBuffer() {
      return body.buffer.slice(body.byteOffset, body.byteOffset + body.byteLength);
    },
    async text() {
      return body.toString("utf8");
    },
  };
};

const pageBytes = decodePageBytesFromHtml(readFileSync(indexHtml, "utf8"));
if (!pageBytes) {
  console.error("boot probe failed: could not decode page bytes from index HTML");
  process.exit(1);
}

const result = await bootFromUrls({
  manifestUrl: manifestPath,
  wasmUrl: wasmPath,
  fetchFn,
  pageBytes,
});

if (expectedTitle !== undefined && result.title !== expectedTitle) {
  console.error(
    `title mismatch: got ${JSON.stringify(result.title)}, expected ${JSON.stringify(expectedTitle)}`
  );
  process.exit(1);
}

console.log(
  `rc_ok boot_title=${JSON.stringify(result.title)} innerText=${JSON.stringify(result.innerText?.slice(0, 120) ?? "")}`
);
