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
const rectNodes = [...svg.querySelectorAll("rect")];
const pathNodes = [...svg.querySelectorAll("path")];
const textNodes = [...svg.querySelectorAll("text")];
const rects = rectNodes.length;
const paths = pathNodes.length;
const texts = textNodes.length;
const labelText = textNodes.map((node) => node.textContent ?? "").join("");
console.log(`svg shapes rect=${rects} path=${paths} text=${texts} label=${JSON.stringify(labelText)}`);
for (const node of rectNodes) {
  console.log(
    `rect x=${JSON.stringify(node.getAttribute("x"))} y=${JSON.stringify(node.getAttribute("y"))} width=${JSON.stringify(node.getAttribute("width"))} height=${JSON.stringify(node.getAttribute("height"))} fill=${JSON.stringify(node.getAttribute("fill"))} stroke=${JSON.stringify(node.getAttribute("stroke"))}`
  );
}
for (const node of pathNodes) {
  const d = node.getAttribute("d") ?? "";
  console.log(`path d=${JSON.stringify(d)}`);
}
for (const node of textNodes) {
  console.log(
    `text content=${JSON.stringify(node.textContent ?? "")} text-anchor=${JSON.stringify(node.getAttribute("text-anchor"))} font-weight=${JSON.stringify(node.getAttribute("font-weight"))} dominant-baseline=${JSON.stringify(node.getAttribute("dominant-baseline"))} font-size=${JSON.stringify(node.getAttribute("font-size"))}`
  );
}
