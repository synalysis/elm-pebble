/**
 * Elm Bytes kernel runtime for elmc WASM web builds.
 *
 * Ports Elm.Kernel.Bytes (elm/bytes) onto RC handles.
 */

export const TAG_BYTES = 16;

const BYTES_CMD_WIDTH = 1;
const BYTES_CMD_READ_U8 = 2;
const BYTES_CMD_READ_U32 = 3;
const BYTES_CMD_READ_BYTES = 4;
const BYTES_CMD_DECODE = 5;
const BYTES_CMD_DECODE_FAILURE = 6;
const BYTES_CMD_FROM_LIST = 7;
const BYTES_CMD_ENCODE = 8;
const BYTES_CMD_READ_F64 = 9;
const BYTES_CMD_READ_STRING = 10;

const ENC_I8 = 1;
const ENC_I16 = 2;
const ENC_I32 = 3;
const ENC_U8 = 4;
const ENC_U16 = 5;
const ENC_U32 = 6;
const ENC_F32 = 7;
const ENC_F64 = 8;
const ENC_SEQ = 9;
const ENC_UTF8 = 10;
const ENC_BYTES = 11;

export function createBytesRuntime(deps) {
  const {
    RC_SUCCESS,
    RC_ERR_UNIMPLEMENTED,
    allocHandle,
    readHandle,
    writeOut,
    intValue,
    newIntHandle,
    invokeClosure,
    listItems,
    tuple2,
    tuple2Ints,
    maybeJustOwn,
    maybeNothing,
    retain,
    release,
    detachTupleSecond,
    TAG_TUPLE2,
    TAG_INT,
    TAG_FLOAT,
    TAG_STRING,
    TAG_CLOSURE,
    stringValue,
  } = deps;

  const newStringHandle = (text) => allocHandle({ tag: TAG_STRING, value: String(text) });

  const newFloatHandle = (value) => allocHandle({ tag: TAG_FLOAT, value: Number(value) });

  /** @type {number} */
  let activeDecodeBytesPtr = 0;

  const withDecodeBytes = (bytesPtr, fn) => {
    const prev = activeDecodeBytesPtr;
    activeDecodeBytesPtr = bytesPtr | 0;
    try {
      return fn();
    } finally {
      activeDecodeBytesPtr = prev;
    }
  };

  const bytesPayload = (ptr) => {
    const payload = readHandle(ptr);
    return payload?.tag === TAG_BYTES ? payload : null;
  };

  const bytesView = (ptr) => {
    const payload = bytesPayload(ptr);
    if (!payload) return null;
    return payload.view;
  };

  const newBytesHandle = (view) => allocHandle({ tag: TAG_BYTES, view });

  const copyBytesSlice = (view, offset, len) => {
    const slice = view.buffer.slice(view.byteOffset + offset, view.byteOffset + offset + len);
    return new DataView(slice);
  };

  const writeTuple2Ints = (outPtr, a, b) => tuple2Ints(outPtr, a | 0, b | 0);

  const writeReadFailure = (outPtr) => writeTuple2Ints(outPtr, -1, 0);

  const TAG_MAYBE = 3;

  const coerceBytesHandle = (ptr) => {
    const handle = ptr | 0;
    if (!handle) return 0;
    if (bytesView(handle)) return handle;

    const payload = readHandle(handle);
    if (payload?.tag === TAG_MAYBE && payload.isJust && payload.value != null) {
      const inner = readHandle(payload.value);
      if (inner?.tag === TAG_BYTES) {
        return payload.value | 0;
      }
    }

    return handle;
  };

  const resolveBytesAndOffset = (params) => {
    const active =
      activeDecodeBytesPtr && bytesView(activeDecodeBytesPtr) ? activeDecodeBytesPtr | 0 : 0;

    const intOffsetFromParams = (items) => {
      for (const ptr of items) {
        const payload = readHandle(ptr);
        if (payload?.tag === TAG_INT) {
          return intValue(ptr) | 0;
        }
      }
      return null;
    };

    if (params.length >= 2) {
      const first = coerceBytesHandle(params[0]);
      const second = coerceBytesHandle(params[1]);
      if (bytesView(first)) {
        return { bytesPtr: first, offset: intValue(second) | 0 };
      }
      if (bytesView(second)) {
        return { bytesPtr: second, offset: intValue(first) | 0 };
      }
      if (active) {
        if (params.length >= 3) {
          const tail = params[params.length - 1] | 0;
          const tailPayload = readHandle(tail);
          if (tailPayload?.tag === TAG_INT) {
            return { bytesPtr: active, offset: intValue(tail) | 0 };
          }
        }
        const offset = intOffsetFromParams(params.slice(1)) ?? intOffsetFromParams(params) ?? 0;
        return { bytesPtr: active, offset };
      }
    }

    if (params.length >= 1) {
      const only = coerceBytesHandle(params[0]);
      if (bytesView(only)) {
        return { bytesPtr: only, offset: 0 };
      }
      if (active) {
        return { bytesPtr: active, offset: intValue(params[0]) | 0 };
      }
    }

    if (active) {
      return { bytesPtr: active, offset: 0 };
    }

    return null;
  };

  const encoderTagAndPayload = (encPtr) => {
    const payload = readHandle(encPtr);
    if (payload?.tag !== TAG_TUPLE2) return null;
    return { tag: intValue(payload.first) | 0, payload: payload.second | 0 };
  };

  const resolveEncoder = (encPtr) => {
    const payload = readHandle(encPtr);
    if (payload?.tag === TAG_CLOSURE) {
      const { rc, value } = invokeClosure(encPtr, []);
      if (rc !== RC_SUCCESS) return 0;
      return value | 0;
    }
    return encPtr | 0;
  };

  const encoderWidth = (encPtr) => {
    const parsed = encoderTagAndPayload(encPtr);
    if (!parsed) return 0;

    switch (parsed.tag) {
      case ENC_I8:
      case ENC_U8:
        return 1;
      case ENC_I16:
      case ENC_U16:
        return 2;
      case ENC_I32:
      case ENC_U32:
      case ENC_F32:
        return 4;
      case ENC_F64:
        return 8;
      case ENC_SEQ: {
        const seq = readHandle(parsed.payload);
        if (seq?.tag !== TAG_TUPLE2) return 0;
        return intValue(seq.first) | 0;
      }
      case ENC_UTF8: {
        const utf8 = readHandle(parsed.payload);
        if (utf8?.tag !== TAG_TUPLE2) return 0;
        return intValue(utf8.first) | 0;
      }
      case ENC_BYTES: {
        const nested = bytesView(parsed.payload);
        return nested ? nested.byteLength | 0 : 0;
      }
      default:
        return 0;
    }
  };

  const writeEncoder = (view, offset, encPtr) => {
    const parsed = encoderTagAndPayload(encPtr);
    if (!parsed) return offset;

    switch (parsed.tag) {
      case ENC_I8:
        view.setInt8(offset, intValue(parsed.payload) | 0);
        return offset + 1;
      case ENC_U8:
        view.setUint8(offset, intValue(parsed.payload) & 0xff);
        return offset + 1;
      case ENC_I16: {
        const inner = encoderTagAndPayload(parsed.payload);
        if (!inner) return offset;
        view.setInt16(offset, intValue(inner.payload) | 0, inner.tag !== 0);
        return offset + 2;
      }
      case ENC_U16: {
        const inner = encoderTagAndPayload(parsed.payload);
        if (!inner) return offset;
        view.setUint16(offset, intValue(inner.payload) | 0, inner.tag !== 0);
        return offset + 2;
      }
      case ENC_I32: {
        const inner = encoderTagAndPayload(parsed.payload);
        if (!inner) return offset;
        view.setInt32(offset, intValue(inner.payload) | 0, inner.tag !== 0);
        return offset + 4;
      }
      case ENC_U32: {
        const inner = encoderTagAndPayload(parsed.payload);
        if (!inner) return offset;
        view.setUint32(offset, intValue(inner.payload) | 0, inner.tag !== 0);
        return offset + 4;
      }
      case ENC_F32: {
        const inner = encoderTagAndPayload(parsed.payload);
        if (!inner) return offset;
        const bits = readHandle(inner.payload);
        const value = bits?.tag === TAG_FLOAT ? bits.value : intValue(inner.payload);
        view.setFloat32(offset, value, inner.tag !== 0);
        return offset + 4;
      }
      case ENC_F64: {
        const inner = encoderTagAndPayload(parsed.payload);
        if (!inner) return offset;
        const bits = readHandle(inner.payload);
        const value = bits?.tag === TAG_FLOAT ? bits.value : intValue(inner.payload);
        view.setFloat64(offset, value, inner.tag !== 0);
        return offset + 8;
      }
      case ENC_SEQ: {
        const seq = readHandle(parsed.payload);
        if (seq?.tag !== TAG_TUPLE2) return offset;
        let cursor = offset;
        for (const itemPtr of listItems(seq.second)) {
          cursor = writeEncoder(view, cursor, itemPtr);
        }
        return cursor;
      }
      case ENC_UTF8: {
        const utf8 = readHandle(parsed.payload);
        if (utf8?.tag !== TAG_TUPLE2) return offset;
        const text = deps.stringValue?.(utf8.second) ?? "";
        const bytes = new TextEncoder().encode(text);
        for (let i = 0; i < bytes.length; i++) {
          view.setUint8(offset + i, bytes[i]);
        }
        return offset + bytes.length;
      }
      case ENC_BYTES: {
        const nested = bytesView(parsed.payload);
        if (!nested) return offset;
        for (let i = 0; i < nested.byteLength; i++) {
          view.setUint8(offset + i, nested.getUint8(i));
        }
        return offset + nested.byteLength;
      }
      default:
        return offset;
    }
  };

  const bytesEncode = (outPtr, encPtr) => {
    const resolved = resolveEncoder(encPtr);
    if (!resolved) {
      writeOut(outPtr, 0);
      return RC_ERR_UNIMPLEMENTED;
    }

    const width = encoderWidth(resolved);
    if (width <= 0) {
      writeOut(outPtr, 0);
      return RC_ERR_UNIMPLEMENTED;
    }

    const buffer = new ArrayBuffer(width);
    const view = new DataView(buffer);
    writeEncoder(view, 0, resolved);
    writeOut(outPtr, newBytesHandle(view));
    return RC_SUCCESS;
  };

  const bytesEncodeSequence = (outPtr, buildersPtr) => {
    // Retain builders for the Seq payload. Elm `sequence builders =
    // Seq (getWidths 0 builders) builders` shares the list; plan/WASM getWidths
    // currently releases the spine during tail recursion, so a post-call retain
    // sees a recycled handle. Build Seq on the host instead.
    const builders = buildersPtr | 0;
    if (builders) retain(null, builders);

    let width = 0;
    for (const itemPtr of listItems(builders)) {
      width += encoderWidth(itemPtr) | 0;
    }

    const widthHandle = newIntHandle(width | 0);
    const inner = allocHandle({ tag: TAG_TUPLE2, first: widthHandle, second: builders });
    const tagHandle = newIntHandle(ENC_SEQ);
    writeOut(outPtr, allocHandle({ tag: TAG_TUPLE2, first: tagHandle, second: inner }));
    return RC_SUCCESS;
  };

  const bytesWidth = (outPtr, bytesPtr) => {
    const view = bytesView(bytesPtr);
    if (!view) {
      writeOut(outPtr, 0);
      return RC_ERR_UNIMPLEMENTED;
    }
    writeOut(outPtr, newIntHandle(view.byteLength | 0));
    return RC_SUCCESS;
  };

  const bytesReadU8 = (outPtr, ...params) => {
    if (typeof process !== "undefined" && process.env && process.env.ELMC_DEBUG_BYTES_READ) {
      console.error("[bytesReadU8] " + JSON.stringify({params: params.map(p => { const h=readHandle(p|0); return h?{tag:h.tag,v:h.value,isJust:h.isJust}:p; })}));
    }

    const resolved = resolveBytesAndOffset(params);
    if (!resolved) {
      writeReadFailure(outPtr);
      return RC_SUCCESS;
    }

    const view = bytesView(resolved.bytesPtr);
    const offset = resolved.offset;
    if (!view || offset < 0 || offset >= view.byteLength) {
      writeReadFailure(outPtr);
      return RC_SUCCESS;
    }

    return writeTuple2Ints(outPtr, offset + 1, view.getUint8(offset));
  };

  const bytesReadU32 = (outPtr, ...params) => {
    if (typeof process !== "undefined" && process.env && process.env.ELMC_DEBUG_BYTES_READ) {
      console.error("[bytesReadU32] " + JSON.stringify({params: params.map(p => { const h=readHandle(p|0); return h?{tag:h.tag,v:h.value,isJust:h.isJust}:p; })}));
    }

    let isLE = true;
    let rest = params;

    if (params.length >= 1) {
      const head = params[0] | 0;
      const headPayload = readHandle(head);
      if (headPayload?.tag === TAG_INT) {
        isLE = intValue(head) !== 0;
        rest = params.slice(1);
      }
    }

    const resolved = resolveBytesAndOffset(rest);
    if (!resolved) {
      writeReadFailure(outPtr);
      return RC_SUCCESS;
    }

    const view = bytesView(resolved.bytesPtr);
    const offset = resolved.offset;
    if (!view || offset < 0 || offset + 4 > view.byteLength) {
      writeReadFailure(outPtr);
      return RC_SUCCESS;
    }

    return writeTuple2Ints(outPtr, offset + 4, view.getUint32(offset, isLE));
  };

  const bytesReadBytes = (outPtr, ...params) => {
    if (typeof process !== "undefined" && process.env && process.env.ELMC_DEBUG_BYTES_READ) {
      console.error("[bytesReadBytes] " + JSON.stringify({params: params.map(p => { const h=readHandle(p|0); return h?{tag:h.tag,v:h.value,isJust:h.isJust}:p; })}));
    }

    let len = 0;
    let rest = params;

    if (params.length >= 1) {
      const head = params[0] | 0;
      const headPayload = readHandle(head);
      if (headPayload?.tag === TAG_INT) {
        len = intValue(head) | 0;
        rest = params.slice(1);
      }
    }

    const resolved = resolveBytesAndOffset(rest);
    if (!resolved) {
      writeReadFailure(outPtr);
      return RC_SUCCESS;
    }

    const view = bytesView(resolved.bytesPtr);
    const offset = resolved.offset;
    if (!view || len < 0 || offset < 0 || offset + len > view.byteLength) {
      writeReadFailure(outPtr);
      return RC_SUCCESS;
    }

    const slice = copyBytesSlice(view, offset, len);
    return tuple2(outPtr, newIntHandle(offset + len), newBytesHandle(slice));
  };

  const bytesReadF64 = (outPtr, ...params) => {
    let isLE = true;
    let rest = params;

    if (params.length >= 1) {
      const head = params[0] | 0;
      const headPayload = readHandle(head);
      if (headPayload?.tag === TAG_INT) {
        isLE = intValue(head) !== 0;
        rest = params.slice(1);
      }
    }

    const resolved = resolveBytesAndOffset(rest);
    if (!resolved) {
      writeReadFailure(outPtr);
      return RC_SUCCESS;
    }

    const view = bytesView(resolved.bytesPtr);
    const offset = resolved.offset;
    if (!view || offset < 0 || offset + 8 > view.byteLength) {
      writeReadFailure(outPtr);
      return RC_SUCCESS;
    }

    const value = view.getFloat64(offset, isLE);
    return tuple2(outPtr, newIntHandle(offset + 8), newFloatHandle(value));
  };

  const bytesReadString = (outPtr, ...params) => {
    let len = 0;
    let rest = params;

    if (params.length >= 1) {
      const head = params[0] | 0;
      const headPayload = readHandle(head);
      if (headPayload?.tag === TAG_INT) {
        len = intValue(head) | 0;
        rest = params.slice(1);
      }
    }

    const resolved = resolveBytesAndOffset(rest);
    if (!resolved) {
      writeReadFailure(outPtr);
      return RC_SUCCESS;
    }

    const view = bytesView(resolved.bytesPtr);
    const offset = resolved.offset;
    if (!view || len < 0 || offset < 0 || offset + len > view.byteLength) {
      writeReadFailure(outPtr);
      return RC_SUCCESS;
    }

    const bytes = new Uint8Array(view.buffer, view.byteOffset + offset, len);
    const text = new TextDecoder("utf-8").decode(bytes);
    return tuple2(outPtr, newIntHandle(offset + len), newStringHandle(text));
  };

  const bytesDecodeFailure = (outPtr) => {
    writeReadFailure(outPtr);
    return RC_SUCCESS;
  };

  const invokeBytesDecoder = (decoderPtr, callArgs) => {
    const payload = readHandle(decoderPtr);
    if (payload?.tag === TAG_TUPLE2) {
      const tag = intValue(payload.first);
      if (tag === 1) {
        return invokeClosure(payload.second, callArgs);
      }
    }
    return invokeClosure(decoderPtr, callArgs);
  };

  const bytesDecode = (outPtr, decoderPtr, bytesPtr) => {
    const resolvedBytes = coerceBytesHandle(bytesPtr);
    const debug = typeof process !== "undefined" && process.env && process.env.ELMC_DEBUG_BYTES_DECODE;
    if (!bytesView(resolvedBytes)) {
      if (debug) console.error("[bytesDecode] no view", bytesPtr, resolvedBytes);
      maybeNothing(outPtr);
      return RC_SUCCESS;
    }

    return withDecodeBytes(resolvedBytes, () => {
      retain(null, resolvedBytes);
      const offsetHandle = newIntHandle(0);
      const startOffset = intValue(offsetHandle) | 0;
      const view = bytesView(resolvedBytes);

      try {
        const { rc, value } = invokeBytesDecoder(decoderPtr, [resolvedBytes, offsetHandle]);

        if (rc !== RC_SUCCESS) {
          if (debug) console.error("[bytesDecode] decoder rc", rc, "len", view?.byteLength);
          maybeNothing(outPtr);
          return RC_SUCCESS;
        }

        const payload = readHandle(value);
        if (payload?.tag !== TAG_TUPLE2) {
          if (debug) console.error("[bytesDecode] not tuple", payload?.tag, value);
          release(value);
          maybeNothing(outPtr);
          return RC_SUCCESS;
        }

        const newOffset = intValue(payload.first);
        const decoded = detachTupleSecond(value);
        if (newOffset < 0 || !decoded || newOffset <= startOffset) {
          if (debug) console.error("[bytesDecode] bad offset/progress", {newOffset, startOffset, decoded: !!decoded, len: view?.byteLength, secondTag: readHandle(decoded)?.tag});
          release(value);
          maybeNothing(outPtr);
          return RC_SUCCESS;
        }

        if (debug) {
          const d = readHandle(decoded);
          let detail = {newOffset, len: view?.byteLength, decodedTag: d?.tag};
          if (d?.tag === TAG_TUPLE2) {
            const f = readHandle(d.first); const s = readHandle(d.second);
            detail.first = f?.tag===1 ? f.value : f?.tag;
            detail.secondTag = s?.tag;
            detail.secondFields = s?.fields?.length;
            if (s?.tag === TAG_TUPLE2) {
              detail.s0 = readHandle(s.first)?.tag===1 ? readHandle(s.first).value : readHandle(s.first)?.tag;
              detail.s1tag = readHandle(s.second)?.tag;
            }
          }
          console.error("[bytesDecode] ok " + JSON.stringify(detail));
        }
        release(value);
        const justRc = maybeJustOwn(outPtr, decoded);
        return justRc;
      } finally {
        release(offsetHandle);
        release(resolvedBytes);
      }
    });
  };

  const bytesFromList = (outPtr, listPtr) => {
    const bytes = new Uint8Array(listItems(listPtr).map((n) => intValue(n) & 0xff));
    writeOut(outPtr, newBytesHandle(new DataView(bytes.buffer)));
    return RC_SUCCESS;
  };

  const bytesCmd = (outPtr, kind, ...params) => {
    switch (kind | 0) {
      case BYTES_CMD_WIDTH:
        return bytesWidth(outPtr, params[0] | 0);

      case BYTES_CMD_READ_U8:
        return bytesReadU8(outPtr, ...params);

      case BYTES_CMD_READ_U32:
        return bytesReadU32(outPtr, ...params);

      case BYTES_CMD_READ_BYTES:
        return bytesReadBytes(outPtr, ...params);

      case BYTES_CMD_DECODE:
        return bytesDecode(outPtr, params[0] | 0, params[1] | 0);

      case BYTES_CMD_DECODE_FAILURE:
        return bytesDecodeFailure(outPtr);

      case BYTES_CMD_FROM_LIST:
        return bytesFromList(outPtr, params[0] | 0);

      case BYTES_CMD_ENCODE:
        return bytesEncode(outPtr, params[0] | 0);

      case BYTES_CMD_READ_F64:
        return bytesReadF64(outPtr, ...params);

      case BYTES_CMD_READ_STRING:
        return bytesReadString(outPtr, ...params);

      default:
        console.warn("[elmc-wasm-runtime] bytes_cmd unimplemented kind", kind, { params });
        writeOut(outPtr, 0);
        return RC_ERR_UNIMPLEMENTED;
    }
  };

  return {
    bytesCmd,
    bytesFromList,
    bytesDecode,
    bytesEncodeSequence,
    newBytesHandle,
    bytesView,
    TAG_BYTES,
  };
}
