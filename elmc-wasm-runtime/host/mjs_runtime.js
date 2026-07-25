/**
 * Host implementation of elm-explorations/linear-algebra's Elm.Kernel.MJS
 * for elmc WASM builds — a direct port of MJS.js (Vector2/Vector3/Vector4/
 * Matrix4) onto the WASM RC handle representation.
 *
 * Every export here is a *value-returning* import (no out-pointer): it reads
 * its argument handles, computes a result, and returns a freshly allocated
 * handle (rc = 1) exactly like `runtime.float_interpolate_from`. Vectors and
 * matrices are boxed as `{ tag: TAG_MJS, kind, data: Float64Array }`; scalar
 * results are boxed as plain `TAG_FLOAT` handles.
 *
 * Record field <-> Float64Array index mapping is derived from the *sorted*
 * field name list (matching Elmc.Backend.Plan.Lower.Record's alphabetical
 * field ordering), not hardcoded per component — see `buildRecordMapping`.
 */

export function createMjsRuntime(deps) {
  const {
    allocHandle,
    readHandle,
    TAG_FLOAT,
    TAG_RECORD,
    TAG_MAYBE,
    TAG_MJS,
    // Optional: when provided, peel single-payload unions (Quantity number).
    TAG_TUPLE2 = 6,
    TAG_INT = 1,
  } = deps;

  // Scalars for MJS ops. elmc encodes single-constructor unions such as
  // `Quantity number = Quantity number` as tuple2(tag, payload). Scene3d /
  // elm-geometry pass those into Matrix4.makePerspective / Vector3 without a
  // host-side unwrap — treat them as their numeric payload, not as 0.
  const numberValue = (ptr, depth = 0) => {
    if (!ptr || depth > 4) return 0;
    const payload = readHandle(ptr);
    if (!payload) return 0;
    if (payload.tag === TAG_FLOAT) return payload.value;
    if (payload.tag === TAG_INT) return payload.value;
    if (payload.tag === TAG_TUPLE2) {
      return numberValue(payload.second | 0, depth + 1);
    }
    if (payload.tag === TAG_RECORD && Array.isArray(payload.fields) && payload.fields.length === 1) {
      return numberValue(payload.fields[0] | 0, depth + 1);
    }
    return 0;
  };

  const newFloatHandle = (value) => allocHandle({ tag: TAG_FLOAT, value });

  const mjsHandle = (kind, data) => allocHandle({ tag: TAG_MJS, kind, data });

  const dataOf = (ptr, expectedLength) => {
    const payload = readHandle(ptr);
    if (payload?.tag === TAG_MJS && payload.data) return payload.data;
    return new Float64Array(expectedLength);
  };

  // Sorted-field-name <-> Float64Array-index mapping, derived from the
  // component name list in the same order the data array is populated.
  // `fieldToData[sortedFieldIndex] = dataIndex`.
  const buildRecordMapping = (dataNames) => {
    const sorted = [...dataNames].sort();
    const fieldToData = sorted.map((name) => dataNames.indexOf(name));
    return { sorted, fieldToData };
  };

  const V2_MAP = buildRecordMapping(["x", "y"]);
  const V3_MAP = buildRecordMapping(["x", "y", "z"]);
  const V4_MAP = buildRecordMapping(["x", "y", "z", "w"]);
  const M4_MAP = buildRecordMapping(
    Array.from({ length: 16 }, (_, i) => {
      const row = (i % 4) + 1;
      const col = Math.floor(i / 4) + 1;
      return `m${row}${col}`;
    })
  );

  const toRecordHandle = (data, map) => {
    const fields = map.fieldToData.map((dataIndex) => newFloatHandle(data[dataIndex]));
    return allocHandle({ tag: TAG_RECORD, fields });
  };

  const fromRecordData = (recordPtr, map) => {
    const fields = readHandle(recordPtr)?.fields ?? [];
    const data = new Float64Array(map.fieldToData.length);
    map.fieldToData.forEach((dataIndex, fieldIndex) => {
      data[dataIndex] = numberValue(fields[fieldIndex]);
    });
    return data;
  };

  // -- Vector2 --------------------------------------------------------------

  const v2 = (xPtr, yPtr) => mjsHandle("v2", new Float64Array([numberValue(xPtr), numberValue(yPtr)]));
  const v2getX = (aPtr) => newFloatHandle(dataOf(aPtr, 2)[0]);
  const v2getY = (aPtr) => newFloatHandle(dataOf(aPtr, 2)[1]);
  const v2setX = (xPtr, aPtr) => {
    const a = dataOf(aPtr, 2);
    return mjsHandle("v2", new Float64Array([numberValue(xPtr), a[1]]));
  };
  const v2setY = (yPtr, aPtr) => {
    const a = dataOf(aPtr, 2);
    return mjsHandle("v2", new Float64Array([a[0], numberValue(yPtr)]));
  };
  const v2toRecord = (aPtr) => toRecordHandle(dataOf(aPtr, 2), V2_MAP);
  const v2fromRecord = (rPtr) => mjsHandle("v2", fromRecordData(rPtr, V2_MAP));
  const v2add = (aPtr, bPtr) => {
    const a = dataOf(aPtr, 2);
    const b = dataOf(bPtr, 2);
    return mjsHandle("v2", new Float64Array([a[0] + b[0], a[1] + b[1]]));
  };
  const v2sub = (aPtr, bPtr) => {
    const a = dataOf(aPtr, 2);
    const b = dataOf(bPtr, 2);
    return mjsHandle("v2", new Float64Array([a[0] - b[0], a[1] - b[1]]));
  };
  const v2negate = (aPtr) => {
    const a = dataOf(aPtr, 2);
    return mjsHandle("v2", new Float64Array([-a[0], -a[1]]));
  };
  const v2lengthLocal = (a) => Math.sqrt(a[0] * a[0] + a[1] * a[1]);
  const v2direction = (aPtr, bPtr) => {
    const a = dataOf(aPtr, 2);
    const b = dataOf(bPtr, 2);
    const r = new Float64Array([a[0] - b[0], a[1] - b[1]]);
    const im = 1.0 / v2lengthLocal(r);
    r[0] *= im;
    r[1] *= im;
    return mjsHandle("v2", r);
  };
  const v2length = (aPtr) => newFloatHandle(v2lengthLocal(dataOf(aPtr, 2)));
  const v2lengthSquared = (aPtr) => {
    const a = dataOf(aPtr, 2);
    return newFloatHandle(a[0] * a[0] + a[1] * a[1]);
  };
  const v2distance = (aPtr, bPtr) => {
    const a = dataOf(aPtr, 2);
    const b = dataOf(bPtr, 2);
    const dx = a[0] - b[0];
    const dy = a[1] - b[1];
    return newFloatHandle(Math.sqrt(dx * dx + dy * dy));
  };
  const v2distanceSquared = (aPtr, bPtr) => {
    const a = dataOf(aPtr, 2);
    const b = dataOf(bPtr, 2);
    const dx = a[0] - b[0];
    const dy = a[1] - b[1];
    return newFloatHandle(dx * dx + dy * dy);
  };
  const v2normalize = (aPtr) => {
    const a = dataOf(aPtr, 2);
    const im = 1.0 / v2lengthLocal(a);
    return mjsHandle("v2", new Float64Array([a[0] * im, a[1] * im]));
  };
  const v2scale = (kPtr, aPtr) => {
    const k = numberValue(kPtr);
    const a = dataOf(aPtr, 2);
    return mjsHandle("v2", new Float64Array([a[0] * k, a[1] * k]));
  };
  const v2dot = (aPtr, bPtr) => {
    const a = dataOf(aPtr, 2);
    const b = dataOf(bPtr, 2);
    return newFloatHandle(a[0] * b[0] + a[1] * b[1]);
  };

  // -- Vector3 --------------------------------------------------------------

  const v3 = (xPtr, yPtr, zPtr) =>
    mjsHandle("v3", new Float64Array([numberValue(xPtr), numberValue(yPtr), numberValue(zPtr)]));
  const v3getX = (aPtr) => newFloatHandle(dataOf(aPtr, 3)[0]);
  const v3getY = (aPtr) => newFloatHandle(dataOf(aPtr, 3)[1]);
  const v3getZ = (aPtr) => newFloatHandle(dataOf(aPtr, 3)[2]);
  const v3setX = (xPtr, aPtr) => {
    const a = dataOf(aPtr, 3);
    return mjsHandle("v3", new Float64Array([numberValue(xPtr), a[1], a[2]]));
  };
  const v3setY = (yPtr, aPtr) => {
    const a = dataOf(aPtr, 3);
    return mjsHandle("v3", new Float64Array([a[0], numberValue(yPtr), a[2]]));
  };
  const v3setZ = (zPtr, aPtr) => {
    const a = dataOf(aPtr, 3);
    return mjsHandle("v3", new Float64Array([a[0], a[1], numberValue(zPtr)]));
  };
  const v3toRecord = (aPtr) => toRecordHandle(dataOf(aPtr, 3), V3_MAP);
  const v3fromRecord = (rPtr) => mjsHandle("v3", fromRecordData(rPtr, V3_MAP));
  const v3add = (aPtr, bPtr) => {
    const a = dataOf(aPtr, 3);
    const b = dataOf(bPtr, 3);
    return mjsHandle("v3", new Float64Array([a[0] + b[0], a[1] + b[1], a[2] + b[2]]));
  };
  const v3subLocal = (a, b) => new Float64Array([a[0] - b[0], a[1] - b[1], a[2] - b[2]]);
  const v3sub = (aPtr, bPtr) => mjsHandle("v3", v3subLocal(dataOf(aPtr, 3), dataOf(bPtr, 3)));
  const v3negate = (aPtr) => {
    const a = dataOf(aPtr, 3);
    return mjsHandle("v3", new Float64Array([-a[0], -a[1], -a[2]]));
  };
  const v3lengthLocal = (a) => Math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]);
  const v3normalizeLocal = (a) => {
    const im = 1.0 / v3lengthLocal(a);
    return new Float64Array([a[0] * im, a[1] * im, a[2] * im]);
  };
  const v3direction = (aPtr, bPtr) =>
    mjsHandle("v3", v3normalizeLocal(v3subLocal(dataOf(aPtr, 3), dataOf(bPtr, 3))));
  const v3length = (aPtr) => newFloatHandle(v3lengthLocal(dataOf(aPtr, 3)));
  const v3lengthSquared = (aPtr) => {
    const a = dataOf(aPtr, 3);
    return newFloatHandle(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]);
  };
  const v3distance = (aPtr, bPtr) => {
    const a = dataOf(aPtr, 3);
    const b = dataOf(bPtr, 3);
    const dx = a[0] - b[0];
    const dy = a[1] - b[1];
    const dz = a[2] - b[2];
    return newFloatHandle(Math.sqrt(dx * dx + dy * dy + dz * dz));
  };
  const v3distanceSquared = (aPtr, bPtr) => {
    const a = dataOf(aPtr, 3);
    const b = dataOf(bPtr, 3);
    const dx = a[0] - b[0];
    const dy = a[1] - b[1];
    const dz = a[2] - b[2];
    return newFloatHandle(dx * dx + dy * dy + dz * dz);
  };
  const v3normalize = (aPtr) => mjsHandle("v3", v3normalizeLocal(dataOf(aPtr, 3)));
  const v3scale = (kPtr, aPtr) => {
    const k = numberValue(kPtr);
    const a = dataOf(aPtr, 3);
    return mjsHandle("v3", new Float64Array([a[0] * k, a[1] * k, a[2] * k]));
  };
  const v3dotLocal = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
  const v3dot = (aPtr, bPtr) => newFloatHandle(v3dotLocal(dataOf(aPtr, 3), dataOf(bPtr, 3)));
  const v3crossLocal = (a, b) =>
    new Float64Array([
      a[1] * b[2] - a[2] * b[1],
      a[2] * b[0] - a[0] * b[2],
      a[0] * b[1] - a[1] * b[0],
    ]);
  const v3cross = (aPtr, bPtr) => mjsHandle("v3", v3crossLocal(dataOf(aPtr, 3), dataOf(bPtr, 3)));
  const v3mul4x4 = (mPtr, vPtr) => {
    const m = dataOf(mPtr, 16);
    const v = dataOf(vPtr, 3);
    const w = v3dotLocal(v, [m[3], m[7], m[11]]) + m[15];
    const r = new Float64Array(3);
    r[0] = (v3dotLocal(v, [m[0], m[4], m[8]]) + m[12]) / w;
    r[1] = (v3dotLocal(v, [m[1], m[5], m[9]]) + m[13]) / w;
    r[2] = (v3dotLocal(v, [m[2], m[6], m[10]]) + m[14]) / w;
    return mjsHandle("v3", r);
  };

  // -- Vector4 --------------------------------------------------------------

  const v4 = (xPtr, yPtr, zPtr, wPtr) =>
    mjsHandle(
      "v4",
      new Float64Array([numberValue(xPtr), numberValue(yPtr), numberValue(zPtr), numberValue(wPtr)])
    );
  const v4getX = (aPtr) => newFloatHandle(dataOf(aPtr, 4)[0]);
  const v4getY = (aPtr) => newFloatHandle(dataOf(aPtr, 4)[1]);
  const v4getZ = (aPtr) => newFloatHandle(dataOf(aPtr, 4)[2]);
  const v4getW = (aPtr) => newFloatHandle(dataOf(aPtr, 4)[3]);
  const v4setX = (xPtr, aPtr) => {
    const a = dataOf(aPtr, 4);
    return mjsHandle("v4", new Float64Array([numberValue(xPtr), a[1], a[2], a[3]]));
  };
  const v4setY = (yPtr, aPtr) => {
    const a = dataOf(aPtr, 4);
    return mjsHandle("v4", new Float64Array([a[0], numberValue(yPtr), a[2], a[3]]));
  };
  const v4setZ = (zPtr, aPtr) => {
    const a = dataOf(aPtr, 4);
    return mjsHandle("v4", new Float64Array([a[0], a[1], numberValue(zPtr), a[3]]));
  };
  const v4setW = (wPtr, aPtr) => {
    const a = dataOf(aPtr, 4);
    return mjsHandle("v4", new Float64Array([a[0], a[1], a[2], numberValue(wPtr)]));
  };
  const v4toRecord = (aPtr) => toRecordHandle(dataOf(aPtr, 4), V4_MAP);
  const v4fromRecord = (rPtr) => mjsHandle("v4", fromRecordData(rPtr, V4_MAP));
  const v4add = (aPtr, bPtr) => {
    const a = dataOf(aPtr, 4);
    const b = dataOf(bPtr, 4);
    return mjsHandle(
      "v4",
      new Float64Array([a[0] + b[0], a[1] + b[1], a[2] + b[2], a[3] + b[3]])
    );
  };
  const v4sub = (aPtr, bPtr) => {
    const a = dataOf(aPtr, 4);
    const b = dataOf(bPtr, 4);
    return mjsHandle(
      "v4",
      new Float64Array([a[0] - b[0], a[1] - b[1], a[2] - b[2], a[3] - b[3]])
    );
  };
  const v4negate = (aPtr) => {
    const a = dataOf(aPtr, 4);
    return mjsHandle("v4", new Float64Array([-a[0], -a[1], -a[2], -a[3]]));
  };
  const v4lengthLocal = (a) => Math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2] + a[3] * a[3]);
  const v4direction = (aPtr, bPtr) => {
    const a = dataOf(aPtr, 4);
    const b = dataOf(bPtr, 4);
    const r = new Float64Array([a[0] - b[0], a[1] - b[1], a[2] - b[2], a[3] - b[3]]);
    const im = 1.0 / v4lengthLocal(r);
    r[0] *= im;
    r[1] *= im;
    r[2] *= im;
    r[3] *= im;
    return mjsHandle("v4", r);
  };
  const v4length = (aPtr) => newFloatHandle(v4lengthLocal(dataOf(aPtr, 4)));
  const v4lengthSquared = (aPtr) => {
    const a = dataOf(aPtr, 4);
    return newFloatHandle(a[0] * a[0] + a[1] * a[1] + a[2] * a[2] + a[3] * a[3]);
  };
  const v4distance = (aPtr, bPtr) => {
    const a = dataOf(aPtr, 4);
    const b = dataOf(bPtr, 4);
    const dx = a[0] - b[0];
    const dy = a[1] - b[1];
    const dz = a[2] - b[2];
    const dw = a[3] - b[3];
    return newFloatHandle(Math.sqrt(dx * dx + dy * dy + dz * dz + dw * dw));
  };
  const v4distanceSquared = (aPtr, bPtr) => {
    const a = dataOf(aPtr, 4);
    const b = dataOf(bPtr, 4);
    const dx = a[0] - b[0];
    const dy = a[1] - b[1];
    const dz = a[2] - b[2];
    const dw = a[3] - b[3];
    return newFloatHandle(dx * dx + dy * dy + dz * dz + dw * dw);
  };
  const v4normalize = (aPtr) => {
    const a = dataOf(aPtr, 4);
    const im = 1.0 / v4lengthLocal(a);
    return mjsHandle("v4", new Float64Array([a[0] * im, a[1] * im, a[2] * im, a[3] * im]));
  };
  const v4scale = (kPtr, aPtr) => {
    const k = numberValue(kPtr);
    const a = dataOf(aPtr, 4);
    return mjsHandle("v4", new Float64Array([a[0] * k, a[1] * k, a[2] * k, a[3] * k]));
  };
  const v4dot = (aPtr, bPtr) => {
    const a = dataOf(aPtr, 4);
    const b = dataOf(bPtr, 4);
    return newFloatHandle(a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3]);
  };

  // -- Matrix4 ----------------------------------------------------------------

  const M4_IDENTITY_DATA = new Float64Array([
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1,
  ]);

  const m4x4identity = () => mjsHandle("m4", new Float64Array(M4_IDENTITY_DATA));
  const m4x4fromRecord = (rPtr) => mjsHandle("m4", fromRecordData(rPtr, M4_MAP));
  const m4x4toRecord = (mPtr) => toRecordHandle(dataOf(mPtr, 16), M4_MAP);

  const m4x4inverse = (mPtr) => {
    const m = dataOf(mPtr, 16);
    const r = new Float64Array(16);

    r[0] =
      m[5] * m[10] * m[15] - m[5] * m[11] * m[14] - m[9] * m[6] * m[15] +
      m[9] * m[7] * m[14] + m[13] * m[6] * m[11] - m[13] * m[7] * m[10];
    r[4] =
      -m[4] * m[10] * m[15] + m[4] * m[11] * m[14] + m[8] * m[6] * m[15] -
      m[8] * m[7] * m[14] - m[12] * m[6] * m[11] + m[12] * m[7] * m[10];
    r[8] =
      m[4] * m[9] * m[15] - m[4] * m[11] * m[13] - m[8] * m[5] * m[15] +
      m[8] * m[7] * m[13] + m[12] * m[5] * m[11] - m[12] * m[7] * m[9];
    r[12] =
      -m[4] * m[9] * m[14] + m[4] * m[10] * m[13] + m[8] * m[5] * m[14] -
      m[8] * m[6] * m[13] - m[12] * m[5] * m[10] + m[12] * m[6] * m[9];
    r[1] =
      -m[1] * m[10] * m[15] + m[1] * m[11] * m[14] + m[9] * m[2] * m[15] -
      m[9] * m[3] * m[14] - m[13] * m[2] * m[11] + m[13] * m[3] * m[10];
    r[5] =
      m[0] * m[10] * m[15] - m[0] * m[11] * m[14] - m[8] * m[2] * m[15] +
      m[8] * m[3] * m[14] + m[12] * m[2] * m[11] - m[12] * m[3] * m[10];
    r[9] =
      -m[0] * m[9] * m[15] + m[0] * m[11] * m[13] + m[8] * m[1] * m[15] -
      m[8] * m[3] * m[13] - m[12] * m[1] * m[11] + m[12] * m[3] * m[9];
    r[13] =
      m[0] * m[9] * m[14] - m[0] * m[10] * m[13] - m[8] * m[1] * m[14] +
      m[8] * m[2] * m[13] + m[12] * m[1] * m[10] - m[12] * m[2] * m[9];
    r[2] =
      m[1] * m[6] * m[15] - m[1] * m[7] * m[14] - m[5] * m[2] * m[15] +
      m[5] * m[3] * m[14] + m[13] * m[2] * m[7] - m[13] * m[3] * m[6];
    r[6] =
      -m[0] * m[6] * m[15] + m[0] * m[7] * m[14] + m[4] * m[2] * m[15] -
      m[4] * m[3] * m[14] - m[12] * m[2] * m[7] + m[12] * m[3] * m[6];
    r[10] =
      m[0] * m[5] * m[15] - m[0] * m[7] * m[13] - m[4] * m[1] * m[15] +
      m[4] * m[3] * m[13] + m[12] * m[1] * m[7] - m[12] * m[3] * m[5];
    r[14] =
      -m[0] * m[5] * m[14] + m[0] * m[6] * m[13] + m[4] * m[1] * m[14] -
      m[4] * m[2] * m[13] - m[12] * m[1] * m[6] + m[12] * m[2] * m[5];
    r[3] =
      -m[1] * m[6] * m[11] + m[1] * m[7] * m[10] + m[5] * m[2] * m[11] -
      m[5] * m[3] * m[10] - m[9] * m[2] * m[7] + m[9] * m[3] * m[6];
    r[7] =
      m[0] * m[6] * m[11] - m[0] * m[7] * m[10] - m[4] * m[2] * m[11] +
      m[4] * m[3] * m[10] + m[8] * m[2] * m[7] - m[8] * m[3] * m[6];
    r[11] =
      -m[0] * m[5] * m[11] + m[0] * m[7] * m[9] + m[4] * m[1] * m[11] -
      m[4] * m[3] * m[9] - m[8] * m[1] * m[7] + m[8] * m[3] * m[5];
    r[15] =
      m[0] * m[5] * m[10] - m[0] * m[6] * m[9] - m[4] * m[1] * m[10] +
      m[4] * m[2] * m[9] + m[8] * m[1] * m[6] - m[8] * m[2] * m[5];

    const det = m[0] * r[0] + m[1] * r[4] + m[2] * r[8] + m[3] * r[12];
    if (det === 0) {
      return allocHandle({ tag: TAG_MAYBE, value: null });
    }

    const invDet = 1.0 / det;
    for (let i = 0; i < 16; i += 1) r[i] *= invDet;

    return allocHandle({ tag: TAG_MAYBE, value: mjsHandle("m4", r), isJust: true });
  };

  const m4x4transposeLocal = (m) => {
    const r = new Float64Array(16);
    r[0] = m[0]; r[1] = m[4]; r[2] = m[8]; r[3] = m[12];
    r[4] = m[1]; r[5] = m[5]; r[6] = m[9]; r[7] = m[13];
    r[8] = m[2]; r[9] = m[6]; r[10] = m[10]; r[11] = m[14];
    r[12] = m[3]; r[13] = m[7]; r[14] = m[11]; r[15] = m[15];
    return r;
  };
  const m4x4transpose = (mPtr) => mjsHandle("m4", m4x4transposeLocal(dataOf(mPtr, 16)));

  const m4x4inverseOrthonormal = (mPtr) => {
    const m = dataOf(mPtr, 16);
    const r = m4x4transposeLocal(m);
    const t = [m[12], m[13], m[14]];
    r[3] = r[7] = r[11] = 0;
    r[12] = -v3dotLocal([r[0], r[4], r[8]], t);
    r[13] = -v3dotLocal([r[1], r[5], r[9]], t);
    r[14] = -v3dotLocal([r[2], r[6], r[10]], t);
    return mjsHandle("m4", r);
  };

  const m4x4makeFrustumLocal = (left, right, bottom, top, znear, zfar) => {
    const r = new Float64Array(16);
    r[0] = (2 * znear) / (right - left);
    r[5] = (2 * znear) / (top - bottom);
    r[8] = (right + left) / (right - left);
    r[9] = (top + bottom) / (top - bottom);
    r[10] = -(zfar + znear) / (zfar - znear);
    r[11] = -1;
    r[14] = (-2 * zfar * znear) / (zfar - znear);
    return r;
  };
  const m4x4makeFrustum = (leftPtr, rightPtr, bottomPtr, topPtr, znearPtr, zfarPtr) =>
    mjsHandle(
      "m4",
      m4x4makeFrustumLocal(
        numberValue(leftPtr),
        numberValue(rightPtr),
        numberValue(bottomPtr),
        numberValue(topPtr),
        numberValue(znearPtr),
        numberValue(zfarPtr)
      )
    );

  const m4x4makePerspective = (fovyPtr, aspectPtr, znearPtr, zfarPtr) => {
    const fovy = numberValue(fovyPtr);
    const aspect = numberValue(aspectPtr);
    const znear = numberValue(znearPtr);
    const zfar = numberValue(zfarPtr);
    const ymax = znear * Math.tan((fovy * Math.PI) / 360.0);
    const ymin = -ymax;
    const xmin = ymin * aspect;
    const xmax = ymax * aspect;
    return mjsHandle("m4", m4x4makeFrustumLocal(xmin, xmax, ymin, ymax, znear, zfar));
  };

  const m4x4makeOrthoLocal = (left, right, bottom, top, znear, zfar) => {
    const r = new Float64Array(16);
    r[0] = 2 / (right - left);
    r[5] = 2 / (top - bottom);
    r[10] = -2 / (zfar - znear);
    r[12] = -(right + left) / (right - left);
    r[13] = -(top + bottom) / (top - bottom);
    r[14] = -(zfar + znear) / (zfar - znear);
    r[15] = 1;
    return r;
  };
  const m4x4makeOrtho = (leftPtr, rightPtr, bottomPtr, topPtr, znearPtr, zfarPtr) =>
    mjsHandle(
      "m4",
      m4x4makeOrthoLocal(
        numberValue(leftPtr),
        numberValue(rightPtr),
        numberValue(bottomPtr),
        numberValue(topPtr),
        numberValue(znearPtr),
        numberValue(zfarPtr)
      )
    );
  const m4x4makeOrtho2D = (leftPtr, rightPtr, bottomPtr, topPtr) =>
    mjsHandle(
      "m4",
      m4x4makeOrthoLocal(
        numberValue(leftPtr),
        numberValue(rightPtr),
        numberValue(bottomPtr),
        numberValue(topPtr),
        -1,
        1
      )
    );

  const m4x4mulLocal = (a, b) => {
    const r = new Float64Array(16);
    const a11 = a[0], a21 = a[1], a31 = a[2], a41 = a[3];
    const a12 = a[4], a22 = a[5], a32 = a[6], a42 = a[7];
    const a13 = a[8], a23 = a[9], a33 = a[10], a43 = a[11];
    const a14 = a[12], a24 = a[13], a34 = a[14], a44 = a[15];
    const b11 = b[0], b21 = b[1], b31 = b[2], b41 = b[3];
    const b12 = b[4], b22 = b[5], b32 = b[6], b42 = b[7];
    const b13 = b[8], b23 = b[9], b33 = b[10], b43 = b[11];
    const b14 = b[12], b24 = b[13], b34 = b[14], b44 = b[15];

    r[0] = a11 * b11 + a12 * b21 + a13 * b31 + a14 * b41;
    r[1] = a21 * b11 + a22 * b21 + a23 * b31 + a24 * b41;
    r[2] = a31 * b11 + a32 * b21 + a33 * b31 + a34 * b41;
    r[3] = a41 * b11 + a42 * b21 + a43 * b31 + a44 * b41;
    r[4] = a11 * b12 + a12 * b22 + a13 * b32 + a14 * b42;
    r[5] = a21 * b12 + a22 * b22 + a23 * b32 + a24 * b42;
    r[6] = a31 * b12 + a32 * b22 + a33 * b32 + a34 * b42;
    r[7] = a41 * b12 + a42 * b22 + a43 * b32 + a44 * b42;
    r[8] = a11 * b13 + a12 * b23 + a13 * b33 + a14 * b43;
    r[9] = a21 * b13 + a22 * b23 + a23 * b33 + a24 * b43;
    r[10] = a31 * b13 + a32 * b23 + a33 * b33 + a34 * b43;
    r[11] = a41 * b13 + a42 * b23 + a43 * b33 + a44 * b43;
    r[12] = a11 * b14 + a12 * b24 + a13 * b34 + a14 * b44;
    r[13] = a21 * b14 + a22 * b24 + a23 * b34 + a24 * b44;
    r[14] = a31 * b14 + a32 * b24 + a33 * b34 + a34 * b44;
    r[15] = a41 * b14 + a42 * b24 + a43 * b34 + a44 * b44;
    return r;
  };
  const m4x4mul = (aPtr, bPtr) => mjsHandle("m4", m4x4mulLocal(dataOf(aPtr, 16), dataOf(bPtr, 16)));

  const m4x4mulAffine = (aPtr, bPtr) => {
    const a = dataOf(aPtr, 16);
    const b = dataOf(bPtr, 16);
    const r = new Float64Array(16);
    const a11 = a[0], a21 = a[1], a31 = a[2];
    const a12 = a[4], a22 = a[5], a32 = a[6];
    const a13 = a[8], a23 = a[9], a33 = a[10];
    const a14 = a[12], a24 = a[13], a34 = a[14];
    const b11 = b[0], b21 = b[1], b31 = b[2];
    const b12 = b[4], b22 = b[5], b32 = b[6];
    const b13 = b[8], b23 = b[9], b33 = b[10];
    const b14 = b[12], b24 = b[13], b34 = b[14];

    r[0] = a11 * b11 + a12 * b21 + a13 * b31;
    r[1] = a21 * b11 + a22 * b21 + a23 * b31;
    r[2] = a31 * b11 + a32 * b21 + a33 * b31;
    r[3] = 0;
    r[4] = a11 * b12 + a12 * b22 + a13 * b32;
    r[5] = a21 * b12 + a22 * b22 + a23 * b32;
    r[6] = a31 * b12 + a32 * b22 + a33 * b32;
    r[7] = 0;
    r[8] = a11 * b13 + a12 * b23 + a13 * b33;
    r[9] = a21 * b13 + a22 * b23 + a23 * b33;
    r[10] = a31 * b13 + a32 * b23 + a33 * b33;
    r[11] = 0;
    r[12] = a11 * b14 + a12 * b24 + a13 * b34 + a14;
    r[13] = a21 * b14 + a22 * b24 + a23 * b34 + a24;
    r[14] = a31 * b14 + a32 * b24 + a33 * b34 + a34;
    r[15] = 1;
    return mjsHandle("m4", r);
  };

  const m4x4makeRotate = (anglePtr, axisPtr) => {
    const angle = numberValue(anglePtr);
    const axis = v3normalizeLocal(dataOf(axisPtr, 3));
    const x = axis[0], y = axis[1], z = axis[2];
    const c = Math.cos(angle);
    const c1 = 1 - c;
    const s = Math.sin(angle);
    const r = new Float64Array(16);

    r[0] = x * x * c1 + c;
    r[1] = y * x * c1 + z * s;
    r[2] = z * x * c1 - y * s;
    r[3] = 0;
    r[4] = x * y * c1 - z * s;
    r[5] = y * y * c1 + c;
    r[6] = y * z * c1 + x * s;
    r[7] = 0;
    r[8] = x * z * c1 + y * s;
    r[9] = y * z * c1 - x * s;
    r[10] = z * z * c1 + c;
    r[11] = 0;
    r[12] = 0;
    r[13] = 0;
    r[14] = 0;
    r[15] = 1;
    return mjsHandle("m4", r);
  };

  const m4x4rotate = (anglePtr, axisPtr, mPtr) => {
    const angle = numberValue(anglePtr);
    const axis = dataOf(axisPtr, 3);
    const m = dataOf(mPtr, 16);
    const im = 1.0 / v3lengthLocal(axis);
    const x = axis[0] * im, y = axis[1] * im, z = axis[2] * im;
    const c = Math.cos(angle);
    const c1 = 1 - c;
    const s = Math.sin(angle);
    const xs = x * s, ys = y * s, zs = z * s;
    const xyc1 = x * y * c1, xzc1 = x * z * c1, yzc1 = y * z * c1;
    const t11 = x * x * c1 + c;
    const t21 = xyc1 + zs;
    const t31 = xzc1 - ys;
    const t12 = xyc1 - zs;
    const t22 = y * y * c1 + c;
    const t32 = yzc1 + xs;
    const t13 = xzc1 + ys;
    const t23 = yzc1 - xs;
    const t33 = z * z * c1 + c;
    const m11 = m[0], m21 = m[1], m31 = m[2], m41 = m[3];
    const m12 = m[4], m22 = m[5], m32 = m[6], m42 = m[7];
    const m13 = m[8], m23 = m[9], m33 = m[10], m43 = m[11];
    const m14 = m[12], m24 = m[13], m34 = m[14], m44 = m[15];
    const r = new Float64Array(16);

    r[0] = m11 * t11 + m12 * t21 + m13 * t31;
    r[1] = m21 * t11 + m22 * t21 + m23 * t31;
    r[2] = m31 * t11 + m32 * t21 + m33 * t31;
    r[3] = m41 * t11 + m42 * t21 + m43 * t31;
    r[4] = m11 * t12 + m12 * t22 + m13 * t32;
    r[5] = m21 * t12 + m22 * t22 + m23 * t32;
    r[6] = m31 * t12 + m32 * t22 + m33 * t32;
    r[7] = m41 * t12 + m42 * t22 + m43 * t32;
    r[8] = m11 * t13 + m12 * t23 + m13 * t33;
    r[9] = m21 * t13 + m22 * t23 + m23 * t33;
    r[10] = m31 * t13 + m32 * t23 + m33 * t33;
    r[11] = m41 * t13 + m42 * t23 + m43 * t33;
    r[12] = m14;
    r[13] = m24;
    r[14] = m34;
    r[15] = m44;
    return mjsHandle("m4", r);
  };

  const m4x4makeScale3Local = (x, y, z) => {
    const r = new Float64Array(16);
    r[0] = x;
    r[5] = y;
    r[10] = z;
    r[15] = 1;
    return r;
  };
  const m4x4makeScale3 = (xPtr, yPtr, zPtr) =>
    mjsHandle("m4", m4x4makeScale3Local(numberValue(xPtr), numberValue(yPtr), numberValue(zPtr)));
  const m4x4makeScale = (vPtr) => {
    const v = dataOf(vPtr, 3);
    return mjsHandle("m4", m4x4makeScale3Local(v[0], v[1], v[2]));
  };

  const m4x4scale3Local = (x, y, z, m) => {
    const r = new Float64Array(16);
    r[0] = m[0] * x; r[1] = m[1] * x; r[2] = m[2] * x; r[3] = m[3] * x;
    r[4] = m[4] * y; r[5] = m[5] * y; r[6] = m[6] * y; r[7] = m[7] * y;
    r[8] = m[8] * z; r[9] = m[9] * z; r[10] = m[10] * z; r[11] = m[11] * z;
    r[12] = m[12]; r[13] = m[13]; r[14] = m[14]; r[15] = m[15];
    return r;
  };
  const m4x4scale3 = (xPtr, yPtr, zPtr, mPtr) =>
    mjsHandle(
      "m4",
      m4x4scale3Local(numberValue(xPtr), numberValue(yPtr), numberValue(zPtr), dataOf(mPtr, 16))
    );
  const m4x4scale = (vPtr, mPtr) => {
    const v = dataOf(vPtr, 3);
    return mjsHandle("m4", m4x4scale3Local(v[0], v[1], v[2], dataOf(mPtr, 16)));
  };

  const m4x4makeTranslate3Local = (x, y, z) => {
    const r = new Float64Array(16);
    r[0] = 1; r[5] = 1; r[10] = 1; r[15] = 1;
    r[12] = x; r[13] = y; r[14] = z;
    return r;
  };
  const m4x4makeTranslate3 = (xPtr, yPtr, zPtr) =>
    mjsHandle(
      "m4",
      m4x4makeTranslate3Local(numberValue(xPtr), numberValue(yPtr), numberValue(zPtr))
    );
  const m4x4makeTranslate = (vPtr) => {
    const v = dataOf(vPtr, 3);
    return mjsHandle("m4", m4x4makeTranslate3Local(v[0], v[1], v[2]));
  };

  const m4x4translate3Local = (x, y, z, m) => {
    const r = new Float64Array(16);
    const m11 = m[0], m21 = m[1], m31 = m[2], m41 = m[3];
    const m12 = m[4], m22 = m[5], m32 = m[6], m42 = m[7];
    const m13 = m[8], m23 = m[9], m33 = m[10], m43 = m[11];
    r[0] = m11; r[1] = m21; r[2] = m31; r[3] = m41;
    r[4] = m12; r[5] = m22; r[6] = m32; r[7] = m42;
    r[8] = m13; r[9] = m23; r[10] = m33; r[11] = m43;
    r[12] = m11 * x + m12 * y + m13 * z + m[12];
    r[13] = m21 * x + m22 * y + m23 * z + m[13];
    r[14] = m31 * x + m32 * y + m33 * z + m[14];
    r[15] = m41 * x + m42 * y + m43 * z + m[15];
    return r;
  };
  const m4x4translate3 = (xPtr, yPtr, zPtr, mPtr) =>
    mjsHandle(
      "m4",
      m4x4translate3Local(numberValue(xPtr), numberValue(yPtr), numberValue(zPtr), dataOf(mPtr, 16))
    );
  const m4x4translate = (vPtr, mPtr) => {
    const v = dataOf(vPtr, 3);
    return mjsHandle("m4", m4x4translate3Local(v[0], v[1], v[2], dataOf(mPtr, 16)));
  };

  const m4x4makeLookAt = (eyePtr, centerPtr, upPtr) => {
    const eye = dataOf(eyePtr, 3);
    const center = dataOf(centerPtr, 3);
    const up = dataOf(upPtr, 3);
    const z = v3normalizeLocal(v3subLocal(eye, center));
    const x = v3normalizeLocal(v3crossLocal(up, z));
    const y = v3normalizeLocal(v3crossLocal(z, x));

    const tm1 = new Float64Array(16);
    tm1[0] = x[0]; tm1[1] = y[0]; tm1[2] = z[0]; tm1[3] = 0;
    tm1[4] = x[1]; tm1[5] = y[1]; tm1[6] = z[1]; tm1[7] = 0;
    tm1[8] = x[2]; tm1[9] = y[2]; tm1[10] = z[2]; tm1[11] = 0;
    tm1[12] = 0; tm1[13] = 0; tm1[14] = 0; tm1[15] = 1;

    const tm2 = new Float64Array(16);
    tm2[0] = 1; tm2[5] = 1; tm2[10] = 1; tm2[15] = 1;
    tm2[12] = -eye[0]; tm2[13] = -eye[1]; tm2[14] = -eye[2];

    return mjsHandle("m4", m4x4mulLocal(tm1, tm2));
  };

  const m4x4makeBasis = (vxPtr, vyPtr, vzPtr) => {
    const vx = dataOf(vxPtr, 3);
    const vy = dataOf(vyPtr, 3);
    const vz = dataOf(vzPtr, 3);
    const r = new Float64Array(16);
    r[0] = vx[0]; r[1] = vx[1]; r[2] = vx[2]; r[3] = 0;
    r[4] = vy[0]; r[5] = vy[1]; r[6] = vy[2]; r[7] = 0;
    r[8] = vz[0]; r[9] = vz[1]; r[10] = vz[2]; r[11] = 0;
    r[12] = 0; r[13] = 0; r[14] = 0; r[15] = 1;
    return mjsHandle("m4", r);
  };

  return {
    v2,
    v2getX,
    v2getY,
    v2setX,
    v2setY,
    v2toRecord,
    v2fromRecord,
    v2add,
    v2sub,
    v2negate,
    v2direction,
    v2length,
    v2lengthSquared,
    v2distance,
    v2distanceSquared,
    v2normalize,
    v2scale,
    v2dot,
    v3,
    v3getX,
    v3getY,
    v3getZ,
    v3setX,
    v3setY,
    v3setZ,
    v3toRecord,
    v3fromRecord,
    v3add,
    v3sub,
    v3negate,
    v3direction,
    v3length,
    v3lengthSquared,
    v3distance,
    v3distanceSquared,
    v3normalize,
    v3scale,
    v3dot,
    v3cross,
    v3mul4x4,
    v4,
    v4getX,
    v4getY,
    v4getZ,
    v4getW,
    v4setX,
    v4setY,
    v4setZ,
    v4setW,
    v4toRecord,
    v4fromRecord,
    v4add,
    v4sub,
    v4negate,
    v4direction,
    v4length,
    v4lengthSquared,
    v4distance,
    v4distanceSquared,
    v4normalize,
    v4scale,
    v4dot,
    m4x4identity,
    m4x4fromRecord,
    m4x4toRecord,
    m4x4inverse,
    m4x4inverseOrthonormal,
    m4x4makeFrustum,
    m4x4makePerspective,
    m4x4makeOrtho,
    m4x4makeOrtho2D,
    m4x4mul,
    m4x4mulAffine,
    m4x4makeRotate,
    m4x4rotate,
    m4x4makeScale3,
    m4x4makeScale,
    m4x4scale3,
    m4x4scale,
    m4x4makeTranslate3,
    m4x4makeTranslate,
    m4x4translate3,
    m4x4translate,
    m4x4makeLookAt,
    m4x4transpose,
    m4x4makeBasis,
  };
}
