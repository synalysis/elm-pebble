import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";
import { loadWasmFromBuildDir } from "./wasm_probe_manifest.js";

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "../../..");
const buildDir = process.argv[2] || join(repoRoot, "elm_pebble_dev/dist/wasm-web");
const routeBytesPath =
  process.argv[3] || join(repoRoot, "elm_pebble_dev/dist/wasm/content.dat");

function installDomStubs() {
  const makeElement = (tag) => {
    const el = {
      tagName: String(tag).toUpperCase(),
      nodeType: 1,
      className: "",
      childNodes: [],
      firstElementChild: null,
      parentNode: null,
      style: {},
      _attrs: {},
      setAttribute(name, value) {
        this._attrs[name] = value;
        if (name === "href") this.href = value;
        if (name === "style") this.style.cssText = value;
      },
      getAttribute(name) {
        return this._attrs[name] ?? null;
      },
      appendChild(child) {
        this.childNodes.push(child);
        child.parentNode = this;
        if (child.nodeType === 1) this.firstElementChild = child;
      },
      replaceChildren(...kids) {
        this.childNodes = kids.filter(Boolean);
        for (const child of this.childNodes) child.parentNode = this;
        this.firstElementChild = this.childNodes.find((c) => c.nodeType === 1) ?? null;
      },
      replaceWith() {},
      remove() {},
      addEventListener() {},
      get textContent() {
        return this.childNodes.map((n) => n.textContent ?? "").join("");
      },
      set textContent(value) {
        this.childNodes = [{ nodeType: 3, textContent: value, childNodes: [] }];
      },
    };
    return el;
  };

  globalThis.Node = { TEXT_NODE: 3, ELEMENT_NODE: 1, DOCUMENT_FRAGMENT_NODE: 11 };
  globalThis.document = {
    title: "",
    body: makeElement("body"),
    getElementById(id) {
      if (id === "app") return this._appRoot ?? null;
      return null;
    },
    createElement: (tag) => makeElement(tag),
    createElementNS: (_ns, tag) => makeElement(tag),
    createTextNode: (text) => ({ nodeType: 3, textContent: text, childNodes: [] }),
    createDocumentFragment: () => ({
      nodeType: 11,
      childNodes: [],
      appendChild(child) {
        this.childNodes.push(child);
      },
    }),
    addEventListener() {},
    removeEventListener() {},
  };
  document._appRoot = makeElement("div");
  document._appRoot.id = "app";
  document.body.appendChild(document._appRoot);

  globalThis.window = {
    location: {
      protocol: "http:",
      hostname: "localhost",
      port: "",
      pathname: "/wasm",
      search: "",
      hash: "",
      href: "http://localhost/wasm",
      origin: "http://localhost",
    },
    history: {
      pushState() {},
      replaceState() {},
      back() {},
      forward() {},
    },
    addEventListener() {},
    scroll() {},
  };
}

installDomStubs();

const { helpers, callExport } = await loadWasmFromBuildDir(buildDir);
const routeBytes = new Uint8Array(readFileSync(routeBytesPath));
helpers.registerRouteBytes?.("/wasm", routeBytes);

const { rc, value: programHandle } = callExport("elmc_fn_Main_main", []);
if (rc !== RC_SUCCESS) {
  console.error(`main failed: rc=${rc}`);
  process.exit(1);
}

const bytesHandle = helpers.newBytesFromUint8Array(routeBytes);

try {
  const boot = helpers.bootBrowserProgram(programHandle, {
    incomingPorts: { pageDataFromJs: bytesHandle },
  });
  console.log(
    JSON.stringify(
      {
        rc: boot.rc,
        stage: boot.stage ?? null,
        title: boot.title ?? document.title,
        bodyKids: document._appRoot?.childNodes?.length ?? 0,
        styles: collectStyles(document._appRoot),
      },
      null,
      2
    )
  );
} catch (err) {
  console.error("boot threw:", err && err.stack ? err.stack : err);
  process.exit(1);
}

function collectStyles(node, out = [], depth = 0) {
  if (!node || depth > 8) return out;
  const style = node._attrs?.style || node.style?.cssText;
  if (style) out.push(style);
  for (const child of node.childNodes ?? []) collectStyles(child, out, depth + 1);
  return out;
}
