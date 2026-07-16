import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { decodePageBytesFromHtml } from "../../../elmc-wasm-runtime/host/page_bytes.js";
import { loadWasmFromBuildDir } from "./wasm_probe_manifest.js";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const [buildDirArg, indexHtmlArg] = process.argv.slice(2);

if (!buildDirArg || !indexHtmlArg) {
  console.error(
    "usage: wasm_browser_elm_pebble_nav_probe_runner.mjs <buildDir> <indexHtmlPath>"
  );
  process.exit(2);
}

const buildDir = resolve(buildDirArg);
const indexHtml = resolve(indexHtmlArg);
const distRoot = dirname(indexHtml);
const gettingStartedHtml = join(distRoot, "getting-started/index.html");
const pageHtmlUrl = pathToFileURL(indexHtml).href;

function installDom() {
  const makeElement = (tag) => ({
    tagName: String(tag).toUpperCase(),
    nodeType: 1,
    childNodes: [],
    parentNode: null,
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
      c.parentNode = this;
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
    },
    addEventListener() {},
    closest(selector) {
      if (selector === "a[href]" && this.tagName === "A" && this.getAttribute("href")) {
        return this;
      }
      for (const child of this.childNodes ?? []) {
        const hit = child.closest?.(selector);
        if (hit) return hit;
      }
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
    baseURI: pageHtmlUrl,
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
    _docListeners: [],
    addEventListener(type, fn, capture) {
      this._docListeners.push({ type, fn, capture: !!capture });
    },
    removeEventListener(type, fn) {
      this._docListeners = this._docListeners.filter((l) => l.fn !== fn);
    },
    dispatchClick(target) {
      const ev = {
        target,
        preventDefault() {
          this.defaultPrevented = true;
        },
      };
      for (const l of this._docListeners) {
        if (l.type === "click" && l.capture) l.fn(ev);
      }
    },
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
    history: {
      pushState(_state, _title, url) {
        const pathname = url.startsWith("http") ? new URL(url).pathname : url;
        window.location.pathname = pathname.split("?")[0].split("#")[0];
        window.location.href = `http://localhost${url.startsWith("/") ? url : `/${url}`}`;
      },
      replaceState() {},
    },
    addEventListener() {},
    scroll() {},
  };
}

installDom();

const pageBytes = decodePageBytesFromHtml(readFileSync(indexHtml, "utf8"));
if (!pageBytes) {
  console.error("nav probe failed: no page bytes in index HTML");
  process.exit(1);
}

const routeBytes = decodePageBytesFromHtml(readFileSync(gettingStartedHtml, "utf8"));
if (!routeBytes) {
  console.error(`nav probe failed: no page bytes in ${gettingStartedHtml}`);
  process.exit(1);
}

const { helpers, callExport } = await loadWasmFromBuildDir(buildDir);
const { rc, value } = callExport("elmc_fn_Main_main", []);
if (rc !== 0) {
  console.error(`main failed rc=${rc}`);
  process.exit(1);
}

helpers.setRouteBytesSiteRoot?.(pageHtmlUrl);
helpers.registerRouteBytes?.("/getting-started", routeBytes);

const bytesHandle = helpers.newBytesFromUint8Array(new Uint8Array(pageBytes));
const boot = helpers.bootBrowserProgram(value, {
  incomingPorts: { pageDataFromJs: bytesHandle },
});

if (boot.rc !== 0) {
  console.error(`boot failed rc=${boot.rc} stage=${boot.stage}`);
  process.exit(1);
}

const initialTitle = document.title;
if (!initialTitle || initialTitle === "Page Data Error") {
  console.error(`nav probe failed: invalid boot title ${JSON.stringify(initialTitle)}`);
  process.exit(1);
}

const findAnchor = (node, href) => {
  if (!node) return null;
  if (node.tagName === "A" && node.getAttribute("href") === href) return node;
  for (const child of node.childNodes ?? []) {
    const hit = findAnchor(child, href);
    if (hit) return hit;
  }
  return null;
};

const startLink = findAnchor(document.getElementById("app"), "/getting-started");
if (!startLink) {
  console.error("nav probe failed: no /getting-started anchor");
  process.exit(1);
}

document.dispatchClick(startLink);

const expectedTitle = "Getting started | Elm Pebble";
const deadline = Date.now() + 5_000;
let lastPath = window.location.pathname;
let lastTitle = document.title;

while (Date.now() < deadline) {
  await new Promise((r) => setTimeout(r, 25));
  lastPath = window.location.pathname;
  lastTitle = document.title;
  if (lastPath === "/getting-started" && lastTitle === expectedTitle) {
    break;
  }
}

if (lastPath !== "/getting-started") {
  console.error(
    `pathname after nav: got ${JSON.stringify(lastPath)}, expected /getting-started`
  );
  process.exit(1);
}

if (lastTitle !== expectedTitle) {
  console.error(
    `title after nav: got ${JSON.stringify(lastTitle)}, expected ${JSON.stringify(expectedTitle)} (path=${JSON.stringify(lastPath)})`
  );
  process.exit(1);
}

console.log(
  `rc_ok elm_pebble_nav initial=${JSON.stringify(initialTitle)} final=${JSON.stringify(lastTitle)} path=${lastPath}`
);
