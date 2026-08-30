import { readFileSync } from "node:fs";
import { parseHTML } from "linkedom";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";

const [buildDir] = process.argv.slice(2);
if (!buildDir) {
  console.error("usage: wasm_svg_attr_ns_probe_runner.mjs <buildDir>");
  process.exit(2);
}

const { document, window } = parseHTML(
  "<!doctype html><html><body><div id='app'></div></body></html>"
);
globalThis.document = document;
globalThis.window = window;
globalThis.Node = window.Node;

const nsCalls = [];
const proto = window.Element?.prototype;
if (proto && typeof proto.setAttributeNS === "function") {
  const orig = proto.setAttributeNS;
  proto.setAttributeNS = function setAttributeNS(ns, name, value) {
    nsCalls.push({
      ns: String(ns ?? ""),
      name: String(name ?? ""),
      value: String(value ?? ""),
    });
    return orig.call(this, ns, name, value);
  };
}

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

await new Promise((r) => setTimeout(r, 20));

const xlink = "http://www.w3.org/1999/xlink";
const hit = nsCalls.find(
  (call) =>
    call.ns === xlink &&
    (call.name === "xlink:href" || call.name === "href") &&
    call.value.includes("example.com/a.png")
);

if (!hit) {
  const image = document.querySelector("image");
  const fallback =
    image &&
    ((typeof image.getAttributeNS === "function" &&
      image.getAttributeNS(xlink, "href")) ||
      image.getAttribute("href") ||
      image.getAttribute("xlink:href"));
  if (!String(fallback || "").includes("example.com/a.png")) {
    console.error(
      `expected VirtualDom.attributeNS xlink:href, nsCalls=${JSON.stringify(nsCalls)} html=${document.body?.innerHTML ?? ""}`
    );
    process.exit(1);
  }
}

const xmlNs = "http://www.w3.org/XML/1998/namespace";
const xmlSpace = nsCalls.find(
  (call) =>
    call.ns === xmlNs &&
    (call.name === "xml:space" || call.name === "space") &&
    call.value === "preserve"
);
if (!xmlSpace) {
  const textEl = document.querySelector("text");
  const spaceAttr =
    textEl &&
    ((typeof textEl.getAttributeNS === "function" &&
      (textEl.getAttributeNS(xmlNs, "space") ||
        textEl.getAttributeNS(xmlNs, "xml:space"))) ||
      textEl.getAttribute("xml:space"));
  if (String(spaceAttr || "") !== "preserve") {
    console.error(
      `expected VirtualDom.attributeNS xml:space, nsCalls=${JSON.stringify(nsCalls)} html=${document.body?.innerHTML ?? ""}`
    );
    process.exit(1);
  }
}

const svgNs = "http://www.w3.org/2000/svg";
const keyed = document.getElementById("keyed");
if (!keyed || keyed.namespaceURI !== svgNs || !String(keyed.textContent || "").includes("A") ||
    !String(keyed.textContent || "").includes("B")) {
  console.error(
    `expected Svg.Keyed.node g in ${svgNs} with A/B, got tag=${keyed?.tagName} ns=${keyed?.namespaceURI} text=${JSON.stringify(keyed?.textContent)} html=${document.body?.innerHTML ?? ""}`
  );
  process.exit(1);
}

helpers.buildImport("release")(programHandle);
if (boot.value) helpers.buildImport("release")(boot.value);
if (boot.initValue) helpers.buildImport("release")(boot.initValue);
if (boot.modelPtr) helpers.buildImport("release")(boot.modelPtr);

console.log("rc_ok svg_attr_ns_ok");
