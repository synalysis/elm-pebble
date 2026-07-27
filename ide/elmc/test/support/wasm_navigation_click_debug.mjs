import { readFileSync } from "node:fs";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";
import { bootFromUrls } from "../../../elmc-wasm-runtime/host/boot.js";
import { decodePageBytesFromHtml } from "../../../elmc-wasm-runtime/host/page_bytes.js";
import { pathToFileURL } from "node:url";

function installDom() {
  const makeEl = (tag) => {
    const el = {
      tagName: tag.toUpperCase(),
      nodeType: 1,
      childNodes: [],
      parentNode: null,
      _listeners: [],
      setAttribute(k, v) {
        this[k === "href" ? "_href" : k] = v;
      },
      getAttribute(k) {
        return k === "href" ? this._href ?? null : this[k] ?? null;
      },
      appendChild(c) {
        this.childNodes.push(c);
        c.parentNode = this;
      },
      replaceChildren(...kids) {
        this.childNodes = [...kids];
      },
      addEventListener(type, fn) {
        this._listeners.push({ type, fn });
      },
      closest(sel) {
        if (sel === "a[href]" && this.tagName === "A") return this;
        for (const c of this.childNodes ?? []) {
          const f = c.closest?.(sel);
          if (f) return f;
        }
        return null;
      },
      dispatchEvent(type, ev = {}) {
        for (const { type: t, fn } of this._listeners) {
          if (t === type) fn(ev);
        }
      },
      get textContent() {
        return this.childNodes.map((n) => n.textContent ?? "").join("");
      },
    };
    return el;
  };

  globalThis.Node = { TEXT_NODE: 3, ELEMENT_NODE: 1 };
  globalThis.document = {
    title: "",
    body: makeEl("body"),
    getElementById(id) {
      return id === "app" ? this._app : null;
    },
    createElement: (tag) => makeEl(tag),
    createElementNS: (_ns, tag) => makeEl(tag),
    createTextNode: (t) => ({ nodeType: 3, textContent: t }),
    createDocumentFragment: () => ({ appendChild() {} }),
    addEventListener(type, fn, capture) {
      this._docListeners = this._docListeners ?? [];
      this._docListeners.push({ type, fn, capture: !!capture });
    },
    removeEventListener(type, fn) {
      this._docListeners = (this._docListeners ?? []).filter((l) => l.fn !== fn);
    },
    dispatchClick(target) {
      const ev = { target, preventDefault() { this.defaultPrevented = true; } };
      for (const l of this._docListeners ?? []) {
        if (l.type === "click" && l.capture) l.fn(ev);
      }
    },
  };
  document._app = makeEl("div");
  document._app.id = "app";

  globalThis.window = {
    location: {
      protocol: "http:",
      hostname: "localhost",
      port: "8080",
      pathname: "/wasm-web/host/browser.html",
      search: "",
      hash: "",
      href: "http://localhost:8080/wasm-web/host/browser.html",
      origin: "http://localhost:8080",
    },
    history: {
      pushState(_s, _t, url) {
        window.location.pathname = url;
        window.location.href = `http://localhost:8080${url}`;
      },
      replaceState() {},
      back() {},
      forward() {},
    },
    addEventListener() {},
    scroll() {},
  };
}

const buildDir = process.argv[2] ?? "tmp/elm_pebble_dev_wasm";
const indexHtml = process.argv[3] ?? "../../elm_pebble_dev/dist/index.html";

installDom();

const html = readFileSync(indexHtml, "utf8");
const pageBytes = decodePageBytesFromHtml(html);
const manifestUrl = pathToFileURL(`${buildDir}/wasm/elmc_wasm.manifest.json`).href;
const wasmUrl = pathToFileURL(`${buildDir}/wasm/app.wasm`).href;
const pageHtmlUrl = pathToFileURL(indexHtml).href;

const fetchFn = (url) => {
  const p = url.startsWith("file:") ? url : url;
  const filePath = p.startsWith("file:") ? decodeURIComponent(p.replace("file://", "")) : p;
  const body = readFileSync(filePath);
  return {
    ok: true,
    async json() {
      return JSON.parse(body.toString());
    },
    async arrayBuffer() {
      return body.buffer.slice(body.byteOffset, body.byteOffset + body.byteLength);
    },
    async text() {
      return body.toString();
    },
  };
};

const result = await bootFromUrls({
  manifestUrl,
  wasmUrl,
  pageHtmlUrl,
  pageBytes,
  fetchFn,
});

console.log("boot title", JSON.stringify(result.title));
console.log("app child count", document.getElementById("app")?.childNodes?.length);
console.log("app html snippet", document.getElementById("app")?.innerHTML?.slice?.(0, 200));

const anchors = [];
const walk = (n) => {
  if (!n) return;
  if (n.tagName === "A") anchors.push({ href: n.getAttribute("href"), text: n.textContent?.trim() });
  for (const c of n.childNodes ?? []) walk(c);
};
walk(document.getElementById("app"));

console.log("anchors sample", anchors.filter((a) => a.text?.includes("Getting started") || a.text === "Docs").slice(0, 5));

const docs = anchors.find((a) => a.text === "Docs");
const docsEl = (() => {
  const find = (n) => {
    if (!n) return null;
    if (n.tagName === "A" && n.textContent?.trim() === "Docs") return n;
    for (const c of n.childNodes ?? []) {
      const f = find(c);
      if (f) return f;
    }
    return null;
  };
  return find(document.getElementById("app"));
})();

if (!docsEl) {
  console.error("no Docs anchor in vdom dom stub");
  process.exit(1);
}

console.log("docs href attr", docsEl.getAttribute("href"));
console.log("doc capture listeners", document._docListeners?.length ?? 0);

document.dispatchClick(docsEl);
await new Promise((r) => setTimeout(r, 100));

console.log("after click path", window.location.pathname, "title", document.title);
