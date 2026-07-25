/**
 * Host-only: MJS numberValue must peel Quantity = tuple2(tag, Float)
 * so Matrix4.makePerspective / Vector3 get real meters/radians, not 0.
 */
import { createMjsRuntime } from "../../../elmc-wasm-runtime/host/mjs_runtime.js";

const TAG_INT = 1;
const TAG_FLOAT = 4;
const TAG_TUPLE2 = 6;
const TAG_RECORD = 11;
const TAG_MAYBE = 3;
const TAG_MJS = 18;

let next = 1;
const handles = new Map();
const allocHandle = (payload) => {
  const id = next++;
  handles.set(id, payload);
  return id;
};
const readHandle = (ptr) => handles.get(ptr | 0) ?? null;

const mjs = createMjsRuntime({
  allocHandle,
  readHandle,
  TAG_FLOAT,
  TAG_RECORD,
  TAG_MAYBE,
  TAG_MJS,
  TAG_TUPLE2,
  TAG_INT,
});

const f = (v) => allocHandle({ tag: TAG_FLOAT, value: v });
const quantity = (v) =>
  allocHandle({
    tag: TAG_TUPLE2,
    first: allocHandle({ tag: TAG_INT, value: 1 }),
    second: f(v),
  });

const near = quantity(0.1);
const far = quantity(100);
const fov = f((32 * Math.PI) / 180);
const aspect = f(720 / 400);

const persp = mjs.m4x4makePerspective(fov, aspect, near, far);
const data = readHandle(persp)?.data;
if (!data || data.length !== 16) {
  console.error("FAIL: expected m4 Float64Array, got", readHandle(persp));
  process.exit(1);
}

// With znear=0 (old bug), m[10]/m[14] explode or become NaN/Inf.
const m10 = data[10];
const m14 = data[14];
const ok =
  Number.isFinite(m10) &&
  Number.isFinite(m14) &&
  Math.abs(m10) < 10 &&
  Math.abs(m14) < 50 &&
  Math.abs(m10 + 1) < 0.5; // perspective: m22 ≈ -1 for typical near/far

if (!ok) {
  console.error("FAIL: perspective looks like Quantity→0 peel miss", Array.from(data));
  process.exit(1);
}

const v = mjs.v3(quantity(1), quantity(2), quantity(3));
const vd = readHandle(v)?.data;
if (!vd || vd[0] !== 1 || vd[1] !== 2 || vd[2] !== 3) {
  console.error("FAIL: v3 Quantity peel", vd && Array.from(vd));
  process.exit(1);
}

console.log(
  JSON.stringify({
    ok: true,
    perspective_m10: m10,
    perspective_m14: m14,
    v3: Array.from(vd),
  })
);
