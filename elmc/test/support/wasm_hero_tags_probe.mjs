import { readFileSync } from "node:fs";
import { RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";
import { loadWasmFromBuildDir } from "./wasm_probe_manifest.js";

// Keep ELMC_DEBUG_* if the caller set them; only clear when unset intentionally.
if (process.env.ELMC_DEBUG_SCENE === "") delete process.env.ELMC_DEBUG_SCENE;
if (process.env.ELMC_DEBUG_WEBGL === "") delete process.env.ELMC_DEBUG_WEBGL;

const buildDir = process.argv[2] || "elm_pebble_dev/dist/wasm-web";
const routeBytesPath = process.argv[3] || "elm_pebble_dev/dist/wasm/content.dat";

// Minimal DOM stubs (subset of wasm_hero_scene_probe.mjs)
const makeEl = (tag) => {
  const el = {
    tagName: String(tag).toUpperCase(),
    nodeType: 1,
    childNodes: [],
    style: {},
    _attrs: {},
    _listeners: [],
    setAttribute(n, v) {
      this._attrs[n] = v;
    },
    getAttribute(n) {
      return this._attrs[n] ?? null;
    },
    appendChild(c) {
      this.childNodes.push(c);
      return c;
    },
    replaceChildren(...kids) {
      this.childNodes = kids.filter(Boolean);
    },
    addEventListener(type, fn) {
      this._listeners.push({ type, fn });
    },
    removeEventListener() {},
    getContext(type) {
      if (String(type).includes("webgl")) {
        return new Proxy(
          {
            clear() {},
            clearColor() {},
            getExtension() {
              return null;
            },
            getParameter() {
              return 0;
            },
            createBuffer() {
              return {};
            },
            createProgram() {
              return {};
            },
            createShader() {
              return {};
            },
            createTexture() {
              return {};
            },
            getProgramParameter() {
              return true;
            },
            getShaderParameter() {
              return true;
            },
            getAttribLocation() {
              return 0;
            },
            getUniformLocation() {
              return {};
            },
            getActiveUniform() {
              return null;
            },
            getActiveAttrib() {
              return null;
            },
            drawingBufferWidth: 720,
            drawingBufferHeight: 400,
          },
          {
            get(t, p) {
              if (p in t) return t[p];
              if (typeof p === "string") {
                const s = () => null;
                t[p] = s;
                return s;
              }
              return undefined;
            },
          }
        );
      }
      return null;
    },
  };
  return el;
};

globalThis.document = {
  body: makeEl("body"),
  title: "",
  getElementById(id) {
    return id === "app" ? this._app : null;
  },
  createElement: makeEl,
  createElementNS: (_ns, t) => makeEl(t),
  createTextNode: (t) => ({ nodeType: 3, textContent: t, childNodes: [] }),
  createDocumentFragment: () => ({
    nodeType: 11,
    childNodes: [],
    appendChild(c) {
      this.childNodes.push(c);
    },
  }),
  _listeners: [],
  addEventListener(type, fn) {
    this._listeners.push({ type, fn });
  },
  removeEventListener() {},
};
document._app = makeEl("div");
document.body.appendChild(document._app);
globalThis.window = {
  location: {
    protocol: "http:",
    hostname: "localhost",
    pathname: "/wasm",
    search: "",
    hash: "",
    href: "http://localhost/wasm",
    origin: "http://localhost",
  },
  history: { pushState() {}, replaceState() {} },
  requestAnimationFrame(cb) {
    if (typeof cb === "function") cb(0);
    return 1;
  },
  cancelAnimationFrame() {},
  setInterval() {
    return 1;
  },
  clearInterval() {},
  addEventListener() {},
  removeEventListener() {},
  innerWidth: 1280,
  innerHeight: 720,
};
globalThis.Node = { TEXT_NODE: 3, ELEMENT_NODE: 1, DOCUMENT_FRAGMENT_NODE: 11 };

const { helpers, callExport } = await loadWasmFromBuildDir(buildDir);
const routeBytes = new Uint8Array(readFileSync(routeBytesPath));
helpers.registerRouteBytes?.("/wasm", routeBytes);
const { rc, value: programHandle } = callExport("elmc_fn_Main_main", []);
if (rc !== RC_SUCCESS) {
  console.error("main fail", rc);
  process.exit(1);
}
const bytesHandle = helpers.newBytesFromUint8Array(routeBytes);
const boot = helpers.bootBrowserProgram(programHandle, {
  incomingPorts: { pageDataFromJs: bytesHandle },
  skipInnerText: true,
});
    console.log(
  JSON.stringify(
    {
      boot: { rc: boot.rc, stage: boot.stage },
      tohtml: globalThis.__ELMC_WEBGL_TOHTML__ || null,
      nodeTags: globalThis.__ELMC_NODE_TAGS__ || null,
      groups: globalThis.__ELMC_GROUP_SNAPS__ || null,
      opaqueBuilt: globalThis.__ELMC_OPAQUE_BUILT__ || null,
      tagMatch: globalThis.__ELMC_TAG_MATCH__ || null,
      opaqueMatchPhase: globalThis.__ELMC_OPAQUE_MATCH_PHASE__ || null,
      maybeJust: globalThis.__ELMC_MAYBE_JUST__ || null,
      gvbNothing: globalThis.__ELMC_GVB_NOTHING__ || null,
      listNil: globalThis.__ELMC_LIST_NIL__ || null,
      webglEntity: globalThis.__ELMC_WEBGL_ENTITY__ || null,
    },
    null,
    2
  )
);
