import { readFileSync } from "node:fs";
import { RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";
import { loadWasmFromBuildDir } from "./wasm_probe_manifest.js";

const buildDir = process.argv[2] || "elm_pebble_dev/dist/wasm-web";

// Minimal stubs so wasm host loads
const makeEl = (tag) => ({
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
  addEventListener() {},
  removeEventListener() {},
  getContext() {
    return null;
  },
});
globalThis.document = {
  body: makeEl("body"),
  title: "",
  getElementById() {
    return null;
  },
  createElement: makeEl,
  createElementNS: (_ns, t) => makeEl(t),
  createTextNode: (t) => ({ nodeType: 3, textContent: t, childNodes: [] }),
  createDocumentFragment: () => ({ nodeType: 11, childNodes: [], appendChild() {} }),
  addEventListener() {},
  removeEventListener() {},
};
globalThis.window = {
  location: { pathname: "/wasm", href: "http://localhost/wasm", protocol: "http:", hostname: "localhost", search: "", hash: "", origin: "http://localhost" },
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

// Reach into runtime via helpers if available; otherwise use callExport + describe via console from host
const describePtr = (ptr, depth = 0) => {
  if (!ptr || depth > 6) return null;
  // helpers may expose readHandle through debug APIs — use union via exports
  // Fall back: call runtime helpers if present
  const h = helpers;
  const read = h.readHandle || h.getHandle || null;
  if (!read) return { ptr, noRead: true, keys: Object.keys(h).slice(0, 40) };

  const payload = read(ptr);
  if (!payload) return { ptr, missing: true };

  const base = { ptr, tag: payload.tag, u: h.unionTagAsInt?.(ptr) };
  switch (payload.tag) {
    case 1: // INT
      return { ...base, value: payload.value };
    case 2: // LIST
      return {
        ...base,
        len: payload.items?.length,
        heads: (payload.items || []).slice(0, 8).map((p) => describePtr(p, depth + 1)),
      };
    case 6: // TUPLE2
      return {
        ...base,
        first: describePtr(payload.first, depth + 1),
        second: describePtr(payload.second, depth + 1),
      };
    case 11: // RECORD
      return {
        ...base,
        nFields: payload.fields?.length,
        fields: (payload.fields || []).slice(0, 6).map((p) => describePtr(p, depth + 1)),
      };
    case 5: // CLOSURE
      return { ...base, arity: payload.arity, id: payload.id };
    case 4: // FLOAT
      return { ...base, value: payload.value };
    default:
      return base;
  }
};

const run = (name, args = []) => {
  const r = callExport(name, args);
  return { name, rc: r.rc, value: r.value | 0, desc: describePtr(r.value) };
};

console.log("helperKeys", Object.keys(helpers).filter((k) => /read|union|handle|list|maybe/i.test(k)));

const results = {};
for (const name of [
  "elmc_fn_HeroScene_elmTangramFace",
  "elmc_fn_HeroScene_floor",
  "elmc_fn_Scene3d_Entity_empty",
]) {
  try {
    results[name] = run(name);
  } catch (e) {
    results[name] = { err: String(e).slice(0, 300) };
  }
}

// If tangram succeeded, peel Entity → Node and call getViewBounds
const tangram = results.elmc_fn_HeroScene_elmTangramFace;
if (tangram?.rc === 0 && tangram.value) {
  // Entity is Tuple2(1, node). Build [node] list and call getViewBounds.
  // Use Camera3d - need a frame. Call with identity-ish via HeroScene path is hard.
  // Instead: Entity.group([tangram]) then inspect.
  const group = run("elmc_fn_Scene3d_Entity_group", [tangram.value]);
  results.groupOfTangram = group;
}

console.log(JSON.stringify(results, null, 2));
