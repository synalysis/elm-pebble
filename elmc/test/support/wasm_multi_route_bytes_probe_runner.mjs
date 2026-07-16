import { readFileSync } from "node:fs";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";

function installDomStubs() {
  const makeElement = (tag) => ({
    tagName: tag,
    nodeType: 1,
    childNodes: [],
    firstElementChild: null,
    parentNode: null,
    setAttribute() {},
    appendChild(child) {
      this.childNodes.push(child);
      child.parentNode = this;
      if (child.nodeType === 1) this.firstElementChild = child;
    },
    replaceChildren(...kids) {
      this.childNodes = [...kids];
    },
    addEventListener() {},
    dispatchEvent() {},
    get textContent() {
      return this.childNodes.map((n) => n.textContent ?? "").join("");
    },
    set textContent(v) {
      this.childNodes = [{ nodeType: 3, textContent: v }];
    },
  });

  globalThis.Node = { TEXT_NODE: 3, ELEMENT_NODE: 1 };
  globalThis.document = {
    title: "",
    body: makeElement("body"),
    getElementById(id) {
      return id === "app" ? this._app : null;
    },
    createElement: (tag) => makeElement(tag),
    createElementNS: (_ns, tag) => makeElement(tag),
    createTextNode: (text) => ({ nodeType: 3, textContent: text }),
    createDocumentFragment: () => ({ appendChild() {} }),
    addEventListener() {},
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
