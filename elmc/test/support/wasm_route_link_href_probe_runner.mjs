import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { decodePageBytesFromHtml } from "../../../elmc-wasm-runtime/host/page_bytes.js";
import { loadWasmFromBuildDir } from "./wasm_probe_manifest.js";

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "../../..");
const buildDir = process.argv[2] ?? join(repoRoot, "elmc/tmp/elm_pebble_dev_wasm");

function installDom() {
  const makeElement = (tag) => ({
    tagName: String(tag).toUpperCase(),
    nodeType: 1,
    childNodes: [],
    _attrs: {},
    setAttribute(k, v) {
      this._attrs[k] = v;
      if (k === "href") this.href = v;
    },
    getAttribute(k) {
      return this._attrs[k] ?? null;
    },
    appendChild(c) {
      this.childNodes.push(c);
    },
    replaceChildren(...kids) {
      const flat = [];
      for (const kid of kids) {
        if (kid?.nodeType === 11 && kid.childNodes?.length) {
          flat.push(...kid.childNodes);
        } else if (kid) {
          flat.push(kid);
        }
      }
      this.childNodes = flat;
    },
    addEventListener() {},
    closest() {
      return null;
    },
    get textContent() {
      return this.childNodes.map((n) => n.textContent ?? "").join("");
    },
  });

  globalThis.Node = { TEXT_NODE: 3, ELEMENT_NODE: 1, DOCUMENT_FRAGMENT_NODE: 11 };
  globalThis.document = {
    title: "",
    body: makeElement("body"),
    getElementById(id) {
      return id === "app" ? this._app : null;
    },
    createElement: (t) => makeElement(t),
    createElementNS: (_, t) => makeElement(t),
    createTextNode: (t) => ({ nodeType: 3, textContent: t, childNodes: [] }),
    createDocumentFragment: () => ({
      nodeType: 11,
      childNodes: [],
      appendChild(c) {
        this.childNodes.push(c);
      },
    }),
    addEventListener() {},
    removeEventListener() {},
  };
  document._app = makeElement("div");
  document._app.id = "app";
  globalThis.window = {
    location: {
      protocol: "http:",
      hostname: "localhost",
      port: "",
      pathname: "/",
      search: "",
      hash: "",
      href: "http://localhost/",
      origin: "http://localhost",
    },
    history: { pushState() {}, replaceState() {} },
    addEventListener() {},
    scroll() {},
  };
}

installDom();

const htmlPath =
  process.env.ELM_PAGES_INDEX_HTML ?? join(repoRoot, "elm_pebble_dev/dist/index.html");
const pageBytes = decodePageBytesFromHtml(readFileSync(htmlPath, "utf8"));
if (!pageBytes) {
  console.error("probe failed: no page bytes in index.html");
  process.exit(1);
}

const { helpers, callExport } = await loadWasmFromBuildDir(buildDir);
const { rc, value } = callExport("elmc_fn_Main_main", []);
if (rc !== 0) {
  console.error(`main failed rc=${rc}`);
  process.exit(1);
}

const bytesHandle = helpers.newBytesFromUint8Array(new Uint8Array(pageBytes));
const boot = helpers.bootBrowserProgram(value, {
  incomingPorts: { pageDataFromJs: bytesHandle },
});

if (boot.rc !== 0) {
  console.error(`boot failed rc=${boot.rc} stage=${boot.stage}`);
  process.exit(1);
}

const anchors = [];
const walk = (n) => {
  if (!n) return;
  if (n.tagName === "A") {
    anchors.push({ href: n.getAttribute("href"), text: (n.textContent ?? "").trim() });
  }
  for (const c of n.childNodes ?? []) walk(c);
};
walk(document.getElementById("app"));

const checks = [
  { text: "Start", expect: "/getting-started" },
  { text: "Docs", expect: "/packages" },
  { text: "FAQ", expect: "/f-a-q" },
];

let failed = false;
for (const { text, expect } of checks) {
  const hit = anchors.find((a) => a.text.includes(text) || a.text === text);
  if (!hit) {
    console.error(`missing anchor: ${JSON.stringify(text)}`);
    failed = true;
    continue;
  }
  if (hit.href !== expect) {
    console.error(
      `href mismatch for ${JSON.stringify(text)}: got ${JSON.stringify(hit.href)}, expected ${JSON.stringify(expect)}`
    );
    failed = true;
  }
}

if (failed) {
  console.error("sample anchors:", JSON.stringify(anchors.slice(0, 15), null, 0));
  process.exit(1);
}

console.log(`rc_ok route_link_hrefs=${anchors.length}`);
