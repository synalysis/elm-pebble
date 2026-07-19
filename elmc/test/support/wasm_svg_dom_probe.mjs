import { readFileSync } from "node:fs";
import { parseHTML } from "linkedom";
import { loadElmcWasm } from "../../../elmc-wasm-runtime/host/loader.js";

const buildDir = process.argv[2];
if (!buildDir) {
  console.error("usage: wasm_svg_dom_probe.mjs <buildDir>");
  process.exit(2);
}

const { document } = parseHTML("<!doctype html><html><body><div id='app'></div></body></html>");
globalThis.document = document;
globalThis.Node = document.defaultView.Node;
globalThis.performance = { now: () => 0 };

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

const { value: programHandle } = callExport("elmc_fn_Main_main", []);
const boot = helpers.bootBrowserProgram(programHandle);
if (boot.rc !== 0) {
  console.error(`boot failed rc=${boot.rc} stage=${boot.stage}`);
  process.exit(1);
}

const svg = document.querySelector("svg");
if (!svg) {
  console.error("no svg found");
  console.error(document.getElementById("app")?.innerHTML?.slice(0, 500));
  process.exit(1);
}

console.log(
  `svg width=${JSON.stringify(svg.getAttribute("width"))} height=${JSON.stringify(svg.getAttribute("height"))} viewBox=${JSON.stringify(svg.getAttribute("viewBox"))} ns=${svg.namespaceURI}`
);
const rects = svg.querySelectorAll("rect").length;
const paths = svg.querySelectorAll("path").length;
const textNodes = svg.querySelectorAll("text");
const texts = textNodes.length;
const labelText = [...textNodes].map((node) => node.textContent ?? "").join("");
console.log(`svg shapes rect=${rects} path=${paths} text=${texts} label=${JSON.stringify(labelText)}`);
