/**
 * Probe: Elm.Kernel.WebGL.entity/toHtml host functions (webgl_runtime.js)
 * against a minimal fake handle store — confirms `entity` returns a
 * TAG_WEBGL_ENTITY handle wrapping its 5 arguments, and `toHtml` returns a
 * TAG_VDOM handle with kind "custom" / renderKey "webgl" wrapping a
 * host-only model object `{entities, options, cache}` (not a handle).
 *
 * usage: node elmc/test/support/wasm_webgl_entity_tohtml_probe_runner.mjs
 */
import { createWebglRuntime } from "../../../elmc-wasm-runtime/host/webgl_runtime.js";

const TAG_RECORD = 11;
const TAG_TUPLE2 = 6;
const TAG_VDOM = 12;
const TAG_LIST = 2;
const TAG_INT = 1;
const TAG_FLOAT = 4;
const TAG_STRING = 7;
const TAG_MJS = 18;
const TAG_WEBGL_ENTITY = 19;

const handles = new Map();
let nextId = 1;
const allocHandle = (payload) => {
  const id = nextId++;
  handles.set(id, payload);
  return id;
};
const readHandle = (ptr) => handles.get(ptr | 0);
const retainCounts = new Map();
const retain = (_out, ptr) => {
  if (!ptr) return;
  retainCounts.set(ptr, (retainCounts.get(ptr) ?? 0) + 1);
};
const listItems = (ptr) => {
  const out = [];
  let cur = ptr | 0;
  while (cur) {
    const payload = readHandle(cur);
    if (payload?.tag !== TAG_LIST && !payload?.items) break;
    out.push(...(payload.items ?? []));
    break;
  }
  return out;
};
const stringValue = (ptr) => {
  const payload = readHandle(ptr);
  return payload?.tag === TAG_STRING ? payload.value : "";
};
const asHandle = (ptr) => {
  if (!ptr) return allocHandle({ tag: TAG_INT, value: 0 });
  if (handles.has(ptr)) return ptr;
  return allocHandle({ tag: TAG_INT, value: ptr | 0 });
};

const runtime = createWebglRuntime({
  allocHandle,
  readHandle,
  retain,
  listItems,
  stringValue,
  asHandle,
  TAG_VDOM,
  TAG_RECORD,
  TAG_TUPLE2,
  TAG_LIST,
  TAG_INT,
  TAG_FLOAT,
  TAG_STRING,
  TAG_MJS,
  TAG_WEBGL_ENTITY,
});

const settingsPtr = allocHandle({ tag: TAG_LIST, items: [] });
const vertPtr = allocHandle({ tag: TAG_RECORD, fields: [] });
const fragPtr = allocHandle({ tag: TAG_RECORD, fields: [] });
const meshPtr = allocHandle({ tag: TAG_INT, value: 0 });
const uniformsPtr = allocHandle({ tag: TAG_RECORD, fields: [] });

const entityPtr = runtime.entity(settingsPtr, vertPtr, fragPtr, meshPtr, uniformsPtr);
const entityPayload = readHandle(entityPtr);

if (entityPayload?.tag !== TAG_WEBGL_ENTITY) {
  console.error("entity() did not return a TAG_WEBGL_ENTITY handle", entityPayload);
  process.exit(1);
}
if (
  entityPayload.settings !== settingsPtr ||
  entityPayload.vert !== vertPtr ||
  entityPayload.frag !== fragPtr ||
  entityPayload.mesh !== meshPtr ||
  entityPayload.uniforms !== uniformsPtr
) {
  console.error("entity() fields do not match {settings, vert, frag, mesh, uniforms}", entityPayload);
  process.exit(1);
}
for (const ptr of [settingsPtr, vertPtr, fragPtr, meshPtr, uniformsPtr]) {
  if ((retainCounts.get(ptr) ?? 0) < 1) {
    console.error("entity() did not retain child handle", ptr);
    process.exit(1);
  }
}

const optionsPtr = allocHandle({ tag: TAG_LIST, items: [] });
const factsPtr = allocHandle({ tag: TAG_LIST, items: [] });
const entitiesPtr = allocHandle({ tag: TAG_LIST, items: [] });

const htmlPtr = runtime.toHtml(optionsPtr, factsPtr, entitiesPtr);
const htmlPayload = readHandle(htmlPtr);

if (htmlPayload?.tag !== TAG_VDOM || htmlPayload.kind !== "custom") {
  console.error("toHtml() did not return a TAG_VDOM custom handle", htmlPayload);
  process.exit(1);
}
if (htmlPayload.renderKey !== "webgl") {
  console.error("toHtml() renderKey mismatch", htmlPayload);
  process.exit(1);
}

// model is a host-only JS object (not a handle pointer) wrapping the
// retained options/entities handles plus a lazily-created draw cache.
const model = htmlPayload.model;
if (!model || model.options !== optionsPtr || model.entities !== entitiesPtr) {
  console.error("toHtml() model mismatch", model);
  process.exit(1);
}
if ((retainCounts.get(optionsPtr) ?? 0) < 1 || (retainCounts.get(entitiesPtr) ?? 0) < 1) {
  console.error("toHtml() did not retain options/entities handles", { optionsPtr, entitiesPtr });
  process.exit(1);
}

if (typeof runtime.render !== "function" || typeof runtime.diff !== "function") {
  console.error("runtime is missing render/diff handlers");
  process.exit(1);
}

// No DOM in this environment: render() must degrade gracefully to null
// rather than throwing.
const rendered = runtime.render(model, []);
if (rendered !== null) {
  console.error("render() without document should return null, got", rendered);
  process.exit(1);
}

console.log("rc_ok webgl_entity_tohtml");
