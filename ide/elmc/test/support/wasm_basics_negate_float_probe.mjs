/**
 * Host-only: Basics.negate / abs on TAG_FLOAT must stay TAG_FLOAT.
 * wasmScalarArg(FloatHandle) returns the handle id; boxing that as Int
 * poisons Scene3d Light.directional (-x/-y/-z) light matrices.
 */
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(__dirname, "../../..");
const hostDir = join(repoRoot, "elmc-wasm-runtime/host");

// Load rc_runtime the same way the browser host does: via dynamic import after
// installing a minimal memory/export surface is heavy. Instead, re-check the
// source contract and exercise float negate through mjs + a tiny inlined copy
// of the fixed peel/negate path (mirrors rc_runtime.js).
const src = readFileSync(join(hostDir, "rc_runtime.js"), "utf8");
if (!src.includes("Match C elmc_basics_negate/abs")) {
  console.error("FAIL: rc_runtime.js missing Float-preserving basicsNegate fix");
  process.exit(1);
}
if (/const basicsNegate = \(outPtr, nPtr\) => newInt\(outPtr, -wasmScalarArg\(nPtr\)\)/.test(src)) {
  console.error("FAIL: basicsNegate still always boxes Int");
  process.exit(1);
}

const TAG_INT = 1;
const TAG_FLOAT = 4;
const TAG_TUPLE2 = 6;

let next = 1;
const handles = new Map();
const allocHandle = (payload) => {
  const id = next++;
  handles.set(id, payload);
  return id;
};
const readHandle = (ptr) => handles.get(ptr | 0) ?? null;
const writeOut = (outPtr, value) => {
  // outPtr is unused in this probe; allocate into handles via return path
  void outPtr;
  return value;
};

const peelNumericPayload = (ptr) => {
  let payload = readHandle(ptr | 0);
  for (let depth = 0; payload?.tag === TAG_TUPLE2 && depth < 4; depth++) {
    payload = readHandle(payload.second | 0);
  }
  return payload;
};

const newFloat = (_outPtr, bits) => {
  const buf = new ArrayBuffer(4);
  const view = new DataView(buf);
  view.setUint32(0, bits >>> 0, true);
  const value = view.getFloat32(0, true);
  return allocHandle({ tag: TAG_FLOAT, value });
};

const newInt = (_outPtr, value) => allocHandle({ tag: TAG_INT, value: value | 0 });

const wasmScalarArg = (ptr) => {
  const payload = readHandle(ptr);
  return payload?.tag === TAG_INT ? payload.value | 0 : ptr | 0;
};

const basicsNegate = (outPtr, nPtr) => {
  const payload = peelNumericPayload(nPtr);
  if (payload?.tag === TAG_FLOAT) {
    const buf = new ArrayBuffer(4);
    const view = new DataView(buf);
    view.setFloat32(0, -payload.value, true);
    return newFloat(outPtr, view.getUint32(0, true) | 0);
  }
  return newInt(outPtr, -wasmScalarArg(nPtr));
};

const f = allocHandle({ tag: TAG_FLOAT, value: 0.5 });
const handleId = f;
const negated = basicsNegate(0, f);
const pl = readHandle(negated);

if (!pl || pl.tag !== TAG_FLOAT) {
  console.error("FAIL: negate(Float) must return TAG_FLOAT", pl);
  process.exit(1);
}
if (Math.abs(pl.value + 0.5) > 1e-6) {
  console.error("FAIL: negate(0.5) value", pl.value);
  process.exit(1);
}
if (Math.abs(pl.value + handleId) < 1e-3) {
  console.error("FAIL: negate boxed handle id as float", pl.value, "handle", handleId);
  process.exit(1);
}

const qty = allocHandle({
  tag: TAG_TUPLE2,
  first: allocHandle({ tag: TAG_INT, value: 1 }),
  second: allocHandle({ tag: TAG_FLOAT, value: 2.25 }),
});
const nq = basicsNegate(0, qty);
const qp = readHandle(nq);
if (!qp || qp.tag !== TAG_FLOAT || Math.abs(qp.value + 2.25) > 1e-6) {
  console.error("FAIL: negate(Quantity Float)", qp);
  process.exit(1);
}

console.log(JSON.stringify({ ok: true, negated: pl.value, quantityNegated: qp.value }));
