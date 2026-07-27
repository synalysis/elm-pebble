import { readFileSync } from "node:fs";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";

function installDomStubs() {
  const elements = new Map();
  let elementId = 0;

  const makeElement = (tag) => {
    const id = ++elementId;
    const el = {
      id: String(id),
      tagName: String(tag).toUpperCase(),
      nodeType: 1,
      className: "",
      childNodes: [],
      firstElementChild: null,
      parentNode: null,
      __vdomKey: undefined,
      _attrs: {},
      setAttribute(name, value) {
        this._attrs[name] = value;
        if (name === "href") this.href = value;
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
        const flat = [];
        for (const kid of kids) {
          if (kid?.nodeType === 11 && kid.childNodes?.length) {
            flat.push(...kid.childNodes);
          } else if (kid) {
            flat.push(kid);
          }
        }
        this.childNodes = flat;
        for (const child of flat) child.parentNode = this;
        this.firstElementChild = flat.find((c) => c.nodeType === 1) ?? null;
      },
      replaceWith(next) {
        if (this.parentNode) {
          const idx = this.parentNode.childNodes.indexOf(this);
          if (idx >= 0) this.parentNode.childNodes[idx] = next;
        }
        next.parentNode = this.parentNode;
      },
      remove() {
        if (this.parentNode) {
          this.parentNode.childNodes = this.parentNode.childNodes.filter((n) => n !== this);
        }
      },
      addEventListener(type, fn) {
        this._listeners = this._listeners ?? [];
        this._listeners.push({ type, fn });
      },
      dispatchEvent(type, event = {}) {
        for (const { type: t, fn } of this._listeners ?? []) {
          if (t === type) fn(event);
        }
      },
      closest(selector) {
        if (selector === "a[href]" && this.tagName === "A" && this.getAttribute("href")) {
          return this;
        }
        for (const child of this.childNodes ?? []) {
          const found = child.closest?.(selector);
          if (found) return found;
        }
        return null;
      },
      get textContent() {
        return this.childNodes.map((n) => n.textContent ?? "").join("");
      },
      set textContent(value) {
        this.childNodes = [{ nodeType: 3, textContent: value, childNodes: [] }];
      },
    };
    elements.set(id, el);
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
    createTextNode: (text) => ({
      nodeType: 3,
      textContent: text,
      childNodes: [],
      appendChild() {},
    }),
    createDocumentFragment: () => ({
      nodeType: 11,
      childNodes: [],
      appendChild(child) {
        this.childNodes.push(child);
      },
    }),
    addEventListener(type, fn, capture) {
      this._docListeners = this._docListeners ?? [];
      this._docListeners.push({ type, fn, capture: !!capture });
    },
    removeEventListener(type, fn) {
      this._docListeners = (this._docListeners ?? []).filter((l) => l.fn !== fn);
    },
    dispatchClick(target) {
      const ev = {
        target,
        preventDefault() {
          this.defaultPrevented = true;
        },
      };
      for (const l of this._docListeners ?? []) {
        if (l.type === "click" && l.capture) l.fn(ev);
      }
    },
  };
  document._appRoot = makeElement("div");
  document._appRoot.id = "app";
  document.body.appendChild(document._appRoot);

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
    history: {
      pushState(_state, _title, url) {
        const pathname = url.startsWith("http") ? new URL(url).pathname : url;
        window.location.pathname = pathname;
        window.location.href = `http://localhost${pathname.startsWith("/") ? pathname : `/${pathname}`}`;
      },
      replaceState(_state, _title, url) {
        const pathname = url.startsWith("http") ? new URL(url).pathname : url;
        window.location.pathname = pathname;
      },
      back() {},
      forward() {},
    },
    addEventListener() {},
    scroll() {},
  };

  globalThis.Date = Date;
  globalThis.performance = performance;
}

const [buildDir] = process.argv.slice(2);
if (!buildDir) {
  console.error("usage: wasm_browser_nav_probe_runner.mjs <buildDir>");
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
  constructorTags: manifest.constructor_tags || {},
});

const { rc, value: programHandle } = callExport("elmc_fn_Main_main", []);
if (rc !== RC_SUCCESS) {
  console.error(`probe failed: rc=${rc}`);
  process.exit(1);
}

const boot = helpers.bootBrowserProgram(programHandle);
if (boot.rc !== RC_SUCCESS) {
  console.error(`browser boot failed: rc=${boot.rc} stage=${boot.stage ?? "unknown"}`);
  process.exit(1);
}

if (boot.title !== "home") {
  console.error(`expected initial title home, got ${JSON.stringify(boot.title)}`);
  process.exit(1);
}

const aboutLink = findAnchor(document._appRoot, "/about");
if (!aboutLink) {
  console.error("probe failed: no /about anchor found");
  process.exit(1);
}

document.dispatchClick(aboutLink);
await new Promise((r) => setTimeout(r, 50));

if (window.location.pathname !== "/about") {
  console.error(
    `expected pathname /about after click, got ${JSON.stringify(window.location.pathname)}`
  );
  process.exit(1);
}

if (document.title !== "about") {
  console.error(`expected title about after nav, got ${JSON.stringify(document.title)}`);
  process.exit(1);
}

console.log(`rc_ok nav_title=${JSON.stringify(document.title)} path=${window.location.pathname}`);

function findAnchor(node, href) {
  if (!node) return null;
  if (node.tagName === "A" && node.getAttribute("href") === href) return node;
  for (const child of node.childNodes ?? []) {
    const found = findAnchor(child, href);
    if (found) return found;
  }
  return null;
}
