/**
 * Elm Json kernel + Json.Decode/Encode runtime for elmc WASM web builds.
 *
 * Ports the semantics of Elm.Kernel.Json (elm/json 1.1.4) onto RC handles.
 */

export const TAG_JSON_DECODER = 14;
export const TAG_JSON_VALUE = 15;

const DEC_SUCCEED = 1;
const DEC_FAIL = 2;
const DEC_PRIM = 3;
const DEC_NULL = 4;
const DEC_LIST = 5;
const DEC_ARRAY = 6;
const DEC_FIELD = 7;
const DEC_INDEX = 8;
const DEC_KEY_VALUE = 9;
const DEC_MAP = 10;
const DEC_AND_THEN = 11;
const DEC_ONE_OF = 12;

const JSON_CMD_WRAP = 1;
const JSON_CMD_ENCODE = 2;
const JSON_CMD_EMPTY_OBJECT = 3;
const JSON_CMD_EMPTY_ARRAY = 4;
const JSON_CMD_ADD_FIELD = 5;
const JSON_CMD_ADD_ENTRY = 6;
const JSON_CMD_ENCODE_NULL = 7;
const JSON_CMD_RUN = 8;
const JSON_CMD_RUN_ON_STRING = 9;
const JSON_CMD_DECODE_STRING = 10;
const JSON_CMD_DECODE_BOOL = 11;
const JSON_CMD_DECODE_INT = 12;
const JSON_CMD_DECODE_FLOAT = 13;
const JSON_CMD_DECODE_VALUE = 14;
const JSON_CMD_DECODE_LIST = 15;
const JSON_CMD_DECODE_ARRAY = 16;
const JSON_CMD_DECODE_NULL = 17;
const JSON_CMD_DECODE_FIELD = 18;
const JSON_CMD_DECODE_INDEX = 19;
const JSON_CMD_DECODE_KEY_VALUE_PAIRS = 20;
const JSON_CMD_MAP1 = 21;
const JSON_CMD_MAP2 = 22;
const JSON_CMD_MAP3 = 23;
const JSON_CMD_MAP4 = 24;
const JSON_CMD_MAP5 = 25;
const JSON_CMD_MAP6 = 26;
const JSON_CMD_MAP7 = 27;
const JSON_CMD_MAP8 = 28;
const JSON_CMD_AND_THEN = 29;
const JSON_CMD_ONE_OF = 30;
const JSON_CMD_SUCCEED = 31;
const JSON_CMD_FAIL = 32;

export function createJsonRuntime(deps) {
  const {
    RC_SUCCESS,
    allocHandle,
    readHandle,
    writeOut,
    intValue,
    stringValue,
    newStringHandle,
    newIntHandle,
    invokeClosure,
    listItems,
    tuple2,
    writeList,
    newList,
    resultOkOwn,
    resultErrOwn,
    asHandle,
    release,
    TAG_INT,
    TAG_FLOAT,
    TAG_STRING,
    TAG_LIST,
    TAG_TUPLE2,
  } = deps;

  const newDecoder = (payload) => allocHandle({ tag: TAG_JSON_DECODER, ...payload });
  const newJsonValue = (value) => allocHandle({ tag: TAG_JSON_VALUE, value });

  const decoderPayload = (ptr) => {
    const payload = readHandle(ptr);
    return payload?.tag === TAG_JSON_DECODER ? payload : null;
  };

  const jsonValuePayload = (ptr) => {
    const payload = readHandle(ptr);
    return payload?.tag === TAG_JSON_VALUE ? payload : null;
  };

  const unwrapJsonValue = (ptr) => {
    const wrapped = jsonValuePayload(ptr);
    if (wrapped) return wrapped.value;
    return elmValueToJs(ptr);
  };

  const wrapElmValue = (ptr) => newJsonValue(elmValueToJs(ptr));

  const elmValueToJs = (ptr) => {
    if (!ptr) return null;
    const payload = readHandle(ptr);
    if (!payload) return null;

    switch (payload.tag) {
      case TAG_INT:
        return payload.value | 0;
      case TAG_FLOAT:
        return payload.value;
      case TAG_STRING:
        return payload.value;
      case TAG_JSON_VALUE:
        return payload.value;
      default:
        return null;
    }
  };

  const jsToElmHandle = (value) => {
    if (typeof value === "number") {
      if (Number.isInteger(value) && value >= -2147483648 && value <= 2147483647) {
        return newIntHandle(value | 0);
      }
      return allocHandle({ tag: TAG_FLOAT, value });
    }
    if (typeof value === "boolean") return newIntHandle(value ? 1 : 0);
    if (typeof value === "string") return newStringHandle(value);
    if (value === null) return newJsonValue(null);
    return newJsonValue(value);
  };

  const isArray = (value) => Array.isArray(value);

  const expecting = (type, value) => ({
    ok: false,
    error: failureError(`Expecting ${type}`, value),
  });

  const failureError = (message, value) =>
    newStringHandle(`${message}` + (value === undefined ? "" : ` (${typeof value})`));

  const primDecoders = {
    string(value) {
      if (typeof value === "string") return { ok: true, handle: newStringHandle(value) };
      if (value instanceof String) return { ok: true, handle: newStringHandle(String(value)) };
      return expecting("an STRING", value);
    },
    bool(value) {
      if (typeof value === "boolean") return { ok: true, handle: newIntHandle(value ? 1 : 0) };
      return expecting("a BOOL", value);
    },
    int(value) {
      if (typeof value !== "number") return expecting("an INT", value);
      if (-2147483647 < value && value < 2147483647 && (value | 0) === value) {
        return { ok: true, handle: newIntHandle(value | 0) };
      }
      if (Number.isFinite(value) && value % 1 === 0) {
        return { ok: true, handle: newIntHandle(value | 0) };
      }
      return expecting("an INT", value);
    },
    float(value) {
      if (typeof value === "number") {
        return { ok: true, handle: allocHandle({ tag: TAG_FLOAT, value }) };
      }
      return expecting("a FLOAT", value);
    },
    value(value) {
      return { ok: true, handle: newJsonValue(value) };
    },
  };

  const runDecoderHelp = (decoderPtr, value) => {
    const decoder = decoderPayload(decoderPtr);
    if (!decoder) return { ok: false, error: failureError("bad decoder", value) };

    switch (decoder.kind) {
      case DEC_PRIM: {
        const prim = primDecoders[decoder.prim];
        return prim ? prim(value) : expecting("valid primitive", value);
      }

      case DEC_SUCCEED:
        return { ok: true, handle: asHandle(decoder.msg) };

      case DEC_FAIL:
        return { ok: false, error: failureError(stringValue(decoder.msg), value) };

      case DEC_NULL:
        return value === null
          ? { ok: true, handle: asHandle(decoder.defaultHandle) }
          : expecting("null", value);

      case DEC_LIST: {
        if (!isArray(value)) return expecting("a LIST", value);
        const items = [];
        for (let i = 0; i < value.length; i++) {
          const step = runDecoderHelp(decoder.decoder, value[i]);
          if (!step.ok) return { ok: false, error: step.error, index: i };
          items.push(asHandle(step.handle));
        }
        return { ok: true, handle: newList(items) };
      }

      case DEC_ARRAY: {
        if (!isArray(value)) return expecting("an ARRAY", value);
        const items = [];
        for (let i = 0; i < value.length; i++) {
          const step = runDecoderHelp(decoder.decoder, value[i]);
          if (!step.ok) return { ok: false, error: step.error, index: i };
          items.push(asHandle(step.handle));
        }
        return { ok: true, handle: newList(items) };
      }

      case DEC_FIELD: {
        if (typeof value !== "object" || value === null || !(decoder.field in value)) {
          return expecting(`an OBJECT with a field named \`${decoder.field}\``, value);
        }
        const step = runDecoderHelp(decoder.decoder, value[decoder.field]);
        if (!step.ok) return { ok: false, error: step.error, field: decoder.field };
        return step;
      }

      case DEC_INDEX: {
        if (!isArray(value)) return expecting("an ARRAY", value);
        if (decoder.index >= value.length) {
          return expecting(
            `a LONGER array. Need index ${decoder.index} but only see ${value.length} entries`,
            value
          );
        }
        const step = runDecoderHelp(decoder.decoder, value[decoder.index]);
        if (!step.ok) return { ok: false, error: step.error, index: decoder.index };
        return step;
      }

      case DEC_KEY_VALUE: {
        if (typeof value !== "object" || value === null || isArray(value)) {
          return expecting("an OBJECT", value);
        }
        const pairs = [];
        for (const key of Object.keys(value)) {
          if (!Object.prototype.hasOwnProperty.call(value, key)) continue;
          const step = runDecoderHelp(decoder.decoder, value[key]);
          if (!step.ok) return { ok: false, error: step.error, field: key };
          const keyHandle = newStringHandle(key);
          const pairHandle = allocHandle({
            tag: TAG_TUPLE2,
            first: keyHandle,
            second: asHandle(step.handle),
          });
          pairs.unshift(pairHandle);
        }
        return { ok: true, handle: newList(pairs) };
      }

      case DEC_MAP: {
        let callee = decoder.func;
        for (const subDecoder of decoder.decoders) {
          const step = runDecoderHelp(subDecoder, value);
          if (!step.ok) return step;
          const invoked = invokeClosure(callee, [asHandle(step.handle)]);
          if (invoked.rc !== RC_SUCCESS) return { ok: false, error: failureError("map callback failed", value) };
          callee = asHandle(invoked.value);
          release(invoked.value);
        }
        return { ok: true, handle: callee };
      }

      case DEC_AND_THEN: {
        const step = runDecoderHelp(decoder.decoder, value);
        if (!step.ok) return step;
        const next = invokeClosure(decoder.callback, [asHandle(step.handle)]);
        if (next.rc !== RC_SUCCESS) return { ok: false, error: failureError("andThen callback failed", value) };
        const result = runDecoderHelp(asHandle(next.value), value);
        release(next.value);
        return result;
      }

      case DEC_ONE_OF: {
        const errors = [];
        for (const subDecoder of decoder.decoders) {
          const step = runDecoderHelp(subDecoder, value);
          if (step.ok) return step;
          errors.unshift(step.error);
        }
        return { ok: false, error: errors[0] ?? failureError("oneOf failed", value) };
      }

      default:
        return { ok: false, error: failureError("unknown decoder", value) };
    }
  };

  const runDecoderToResult = (outPtr, decoderPtr, jsValue) => {
    const step = runDecoderHelp(decoderPtr, jsValue);
    if (step.ok) return resultOkOwn(outPtr, asHandle(step.handle));
    return resultErrOwn(outPtr, asHandle(step.error));
  };

  const writeDecoderOut = (outPtr, payload) => {
    writeOut(outPtr, newDecoder(payload));
    return RC_SUCCESS;
  };

  const primDecoder = (name) => ({ kind: DEC_PRIM, prim: name });

  const jsonCmd = (outPtr, kind, ...params) => {
    switch (kind | 0) {
      case JSON_CMD_WRAP: {
        writeOut(outPtr, wrapElmValue(params[0] | 0));
        return RC_SUCCESS;
      }

      case JSON_CMD_ENCODE: {
        const indent = intValue(params[0] | 0);
        const text = JSON.stringify(unwrapJsonValue(params[1] | 0), null, indent);
        writeOut(outPtr, newStringHandle(text));
        return RC_SUCCESS;
      }

      case JSON_CMD_EMPTY_OBJECT: {
        writeOut(outPtr, newJsonValue({}));
        return RC_SUCCESS;
      }

      case JSON_CMD_EMPTY_ARRAY: {
        writeOut(outPtr, newJsonValue([]));
        return RC_SUCCESS;
      }

      case JSON_CMD_ENCODE_NULL: {
        writeOut(outPtr, newJsonValue(null));
        return RC_SUCCESS;
      }

      case JSON_CMD_ADD_FIELD: {
        const key = stringValue(params[0] | 0);
        const objectPtr = params[2] | 0;
        const object = jsonValuePayload(objectPtr);
        if (object && typeof object.value === "object" && object.value !== null && !Array.isArray(object.value)) {
          const unwrapped = unwrapJsonValue(params[1] | 0);
          if (!(key === "toJSON" && typeof unwrapped === "function")) {
            object.value[key] = unwrapped;
          }
        }
        writeOut(outPtr, objectPtr);
        return RC_SUCCESS;
      }

      case JSON_CMD_ADD_ENTRY: {
        const funcPtr = params[0] | 0;
        const entryPtr = params[1] | 0;
        const arrayPtr = params[2] | 0;
        const array = jsonValuePayload(arrayPtr);
        if (array && Array.isArray(array.value)) {
          const encoded = invokeClosure(funcPtr, [asHandle(entryPtr)]);
          if (encoded.rc !== RC_SUCCESS) {
            writeOut(outPtr, 0);
            return encoded.rc;
          }
          array.value.push(unwrapJsonValue(asHandle(encoded.value)));
          release(encoded.value);
        }
        writeOut(outPtr, arrayPtr);
        return RC_SUCCESS;
      }

      case JSON_CMD_RUN: {
        const decoderPtr = params[0] | 0;
        const valuePtr = params[1] | 0;
        return runDecoderToResult(outPtr, decoderPtr, unwrapJsonValue(valuePtr));
      }

      case JSON_CMD_RUN_ON_STRING: {
        const decoderPtr = params[0] | 0;
        const stringPtr = params[1] | 0;
        try {
          const parsed = JSON.parse(stringValue(stringPtr));
          return runDecoderToResult(outPtr, decoderPtr, parsed);
        } catch (err) {
          return resultErrOwn(
            outPtr,
            newStringHandle(`This is not valid JSON! ${err?.message ?? err}`)
          );
        }
      }

      case JSON_CMD_DECODE_STRING:
        return writeDecoderOut(outPtr, primDecoder("string"));

      case JSON_CMD_DECODE_BOOL:
        return writeDecoderOut(outPtr, primDecoder("bool"));

      case JSON_CMD_DECODE_INT:
        return writeDecoderOut(outPtr, primDecoder("int"));

      case JSON_CMD_DECODE_FLOAT:
        return writeDecoderOut(outPtr, primDecoder("float"));

      case JSON_CMD_DECODE_VALUE:
        return writeDecoderOut(outPtr, primDecoder("value"));

      case JSON_CMD_DECODE_LIST:
        return writeDecoderOut(outPtr, { kind: DEC_LIST, decoder: params[0] | 0 });

      case JSON_CMD_DECODE_ARRAY:
        return writeDecoderOut(outPtr, { kind: DEC_ARRAY, decoder: params[0] | 0 });

      case JSON_CMD_DECODE_NULL:
        return writeDecoderOut(outPtr, { kind: DEC_NULL, defaultHandle: params[0] | 0 });

      case JSON_CMD_DECODE_FIELD:
        return writeDecoderOut(outPtr, {
          kind: DEC_FIELD,
          field: stringValue(params[0] | 0),
          decoder: params[1] | 0,
        });

      case JSON_CMD_DECODE_INDEX:
        return writeDecoderOut(outPtr, {
          kind: DEC_INDEX,
          index: intValue(params[0] | 0),
          decoder: params[1] | 0,
        });

      case JSON_CMD_DECODE_KEY_VALUE_PAIRS:
        return writeDecoderOut(outPtr, { kind: DEC_KEY_VALUE, decoder: params[0] | 0 });

      case JSON_CMD_SUCCEED:
        return writeDecoderOut(outPtr, { kind: DEC_SUCCEED, msg: params[0] | 0 });

      case JSON_CMD_FAIL:
        return writeDecoderOut(outPtr, { kind: DEC_FAIL, msg: params[0] | 0 });

      case JSON_CMD_AND_THEN:
        return writeDecoderOut(outPtr, {
          kind: DEC_AND_THEN,
          callback: params[0] | 0,
          decoder: params[1] | 0,
        });

      case JSON_CMD_ONE_OF:
        return writeDecoderOut(outPtr, {
          kind: DEC_ONE_OF,
          decoders: listItems(params[0] | 0).map((item) => asHandle(item)),
        });

      case JSON_CMD_MAP1:
        return writeDecoderOut(outPtr, {
          kind: DEC_MAP,
          func: params[0] | 0,
          decoders: [params[1] | 0],
        });

      case JSON_CMD_MAP2:
        return writeDecoderOut(outPtr, {
          kind: DEC_MAP,
          func: params[0] | 0,
          decoders: [params[1] | 0, params[2] | 0],
        });

      case JSON_CMD_MAP3:
        return writeDecoderOut(outPtr, {
          kind: DEC_MAP,
          func: params[0] | 0,
          decoders: [params[1] | 0, params[2] | 0, params[3] | 0],
        });

      case JSON_CMD_MAP4:
        return writeDecoderOut(outPtr, {
          kind: DEC_MAP,
          func: params[0] | 0,
          decoders: [params[1] | 0, params[2] | 0, params[3] | 0, params[4] | 0],
        });

      case JSON_CMD_MAP5:
        return writeDecoderOut(outPtr, {
          kind: DEC_MAP,
          func: params[0] | 0,
          decoders: [params[1] | 0, params[2] | 0, params[3] | 0, params[4] | 0, params[5] | 0],
        });

      case JSON_CMD_MAP6:
        return writeDecoderOut(outPtr, {
          kind: DEC_MAP,
          func: params[0] | 0,
          decoders: [
            params[1] | 0,
            params[2] | 0,
            params[3] | 0,
            params[4] | 0,
            params[5] | 0,
            params[6] | 0,
          ],
        });

      case JSON_CMD_MAP7:
        return writeDecoderOut(outPtr, {
          kind: DEC_MAP,
          func: params[0] | 0,
          decoders: [
            params[1] | 0,
            params[2] | 0,
            params[3] | 0,
            params[4] | 0,
            params[5] | 0,
            params[6] | 0,
            params[7] | 0,
          ],
        });

      case JSON_CMD_MAP8:
        return writeDecoderOut(outPtr, {
          kind: DEC_MAP,
          func: params[0] | 0,
          decoders: [
            params[1] | 0,
            params[2] | 0,
            params[3] | 0,
            params[4] | 0,
            params[5] | 0,
            params[6] | 0,
            params[7] | 0,
            params[8] | 0,
          ],
        });

      default:
        console.warn("[elmc-wasm-runtime] json_cmd unimplemented kind", kind, { params });
        writeOut(outPtr, 0);
        return deps.RC_ERR_UNIMPLEMENTED ?? 100;
    }
  };

  const jsonDecodeRun = (outPtr, decoderPtr, valuePtr) =>
    runDecoderToResult(outPtr, decoderPtr, unwrapJsonValue(valuePtr));

  const jsonDecodeRunString = (outPtr, decoderPtr, stringPtr) => {
    try {
      const parsed = JSON.parse(stringValue(stringPtr));
      return runDecoderToResult(outPtr, decoderPtr, parsed);
    } catch (err) {
      return resultErrOwn(
        outPtr,
        newStringHandle(`This is not valid JSON! ${err?.message ?? err}`)
      );
    }
  };

  const jsonEncodeFromPairs = (outPtr, pairsPtr) => {
    const object = {};
    for (const entryPtr of listItems(pairsPtr)) {
      const pair = readHandle(entryPtr);
      if (pair?.tag === TAG_TUPLE2) {
        const key = stringValue(pair.first);
        object[key] = unwrapJsonValue(pair.second);
      }
    }
    writeOut(outPtr, newJsonValue(object));
    return RC_SUCCESS;
  };

  const jsonEncodeListLike = (outPtr, funcPtr, itemsPtr) => {
    const array = [];
    for (const item of listItems(itemsPtr)) {
      const { rc, value } = invokeClosure(funcPtr, [asHandle(item)]);
      if (rc !== RC_SUCCESS) {
        writeOut(outPtr, 0);
        return rc;
      }
      array.push(unwrapJsonValue(asHandle(value)));
      release(value);
    }
    writeOut(outPtr, newJsonValue(array));
    return RC_SUCCESS;
  };

  return {
    jsonCmd,
    jsonDecodeRun,
    jsonDecodeRunString,
    jsonEncodeFromPairs,
    jsonEncodeListLike,
    writeDecoderOut,
    newDecoder,
    primDecoder,
    newJsonValue,
    unwrapJsonValue,
    runDecoderToResult,
    DEC_LIST,
    DEC_ARRAY,
    DEC_FIELD,
    DEC_INDEX,
    DEC_KEY_VALUE,
    DEC_MAP,
    DEC_AND_THEN,
    DEC_ONE_OF,
    DEC_NULL,
    DEC_SUCCEED,
    DEC_FAIL,
  };
}
