import { readFileSync } from "node:fs";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";

function installDomStubs() {
  const flattenKids = (kids) => {
    const out = [];
    for (const kid of kids) {
      if (kid && kid.nodeType === 11) {
        out.push(...kid.childNodes.splice(0, kid.childNodes.length));
      } else if (kid != null) {
        out.push(kid);
      }
    }
    return out;
  };

  const attachReplaceWith = (node) => {
    node.replaceWith = function replaceWith(...nodes) {
      const parent = this.parentNode;
      if (!parent) return;
      const index = parent.childNodes.indexOf(this);
      if (index < 0) return;
      const flat = flattenKids(nodes);
      parent.childNodes.splice(index, 1, ...flat);
      this.parentNode = null;
      for (const n of flat) n.parentNode = parent;
      if (typeof parent.firstElementChild !== "undefined") {
        parent.firstElementChild =
          parent.childNodes.find((c) => c?.nodeType === 1) ?? null;
      }
    };
    return node;
  };

  const makeElement = (tag) =>
    attachReplaceWith({
      tagName: tag,
      nodeType: 1,
      childNodes: [],
      firstElementChild: null,
      parentNode: null,
      id: "",
      setAttribute(name, value) {
        if (name === "id") this.id = value;
      },
      appendChild(child) {
        const nodes =
          child && child.nodeType === 11
            ? child.childNodes.splice(0, child.childNodes.length)
            : [child];
        for (const node of nodes) {
          this.childNodes.push(node);
          node.parentNode = this;
          if (node.nodeType === 1 && !this.firstElementChild) {
            this.firstElementChild = node;
          }
        }
        return child;
      },
      replaceChildren(...kids) {
        for (const child of this.childNodes) child.parentNode = null;
        const flat = flattenKids(kids);
        this.childNodes = flat;
        for (const child of flat) child.parentNode = this;
        this.firstElementChild = flat.find((c) => c?.nodeType === 1) ?? null;
      },
      replaceChild(next, prev) {
        const index = this.childNodes.indexOf(prev);
        if (index < 0) return prev;
        this.childNodes[index] = next;
        prev.parentNode = null;
        next.parentNode = this;
        this.firstElementChild = this.childNodes.find((c) => c?.nodeType === 1) ?? null;
        return prev;
      },
      addEventListener() {},
      dispatchEvent() {
        return true;
      },
      get textContent() {
        return this.childNodes.map((n) => n.textContent ?? "").join("");
      },
      set textContent(v) {
        this.childNodes = [
          attachReplaceWith({
            nodeType: 3,
            textContent: String(v),
            childNodes: [],
            parentNode: null,
          }),
        ];
        this.firstElementChild = null;
      },
    });

  globalThis.Node = { TEXT_NODE: 3, ELEMENT_NODE: 1, DOCUMENT_FRAGMENT_NODE: 11 };
  globalThis.document = {
    title: "",
    body: makeElement("body"),
    getElementById(id) {
      return id === "app" ? this._app : null;
    },
    createElement: (tag) => makeElement(tag),
    createElementNS: (_ns, tag) => makeElement(tag),
    createTextNode: (text) =>
      attachReplaceWith({
        nodeType: 3,
        textContent: text,
        childNodes: [],
        parentNode: null,
      }),
    createDocumentFragment: () => ({
      nodeType: 11,
      childNodes: [],
      appendChild(child) {
        this.childNodes.push(child);
        child.parentNode = this;
        return child;
      },
    }),
    addEventListener() {},
  };
  document._app = makeElement("div");
  document._app.id = "app";
  document.body.appendChild(document._app);

  globalThis.window = {
    location: {
      protocol: "http:",
      hostname: "localhost",
      port: "",
      pathname: "/",
      search: "",
      hash: "",
      href: "http://localhost/",
    },
    history: {
      pushState(_s, _t, url) {
        window.location.pathname = url;
      },
      replaceState() {},
      back() {},
      forward() {},
    },
    addEventListener() {},
    scroll() {},
  };
}

const [buildDir] = process.argv.slice(2);
if (!buildDir) {
  console.error("usage: wasm_multi_route_bytes_probe_runner.mjs <buildDir>");
  process.exit(2);
}

installDomStubs();

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
});

const { rc, value: programHandle } = callExport("elmc_fn_Main_main", []);
if (rc !== RC_SUCCESS) {
  console.error(`probe failed: rc=${rc}`);
  process.exit(1);
}

helpers.registerRouteBytes?.("/", new Uint8Array([1]));
helpers.registerRouteBytes?.("/about", new Uint8Array([2]));

const homeBytes = helpers.newBytesFromUint8Array(new Uint8Array([1]));
const boot = helpers.bootBrowserProgram(programHandle, {
  incomingPorts: { pageDataFromJs: homeBytes },
});

if (boot.rc !== RC_SUCCESS) {
  console.error(`boot failed: rc=${boot.rc} stage=${boot.stage ?? "unknown"}`);
  process.exit(1);
}

if (boot.title !== "home") {
  console.error(`expected title home after boot, got ${JSON.stringify(boot.title)}`);
  process.exit(1);
}

window.location.pathname = "/about";
window.location.href = "http://localhost/about";
await helpers.deliverIncomingPort("pageDataFromJs", new Uint8Array([2]));

if (document.title !== "about" && boot.title !== "about") {
  console.error(`expected title about after nav, got title=${JSON.stringify(document.title)}`);
  process.exit(1);
}

console.log("rc_ok multi_route_bytes_ok");
