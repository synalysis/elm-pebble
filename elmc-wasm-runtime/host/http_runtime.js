/**
 * Browser Http kernel runtime for elmc WASM web builds.
 */

import { TASK_HTTP_ELM } from "./task_runtime.js";

export function createHttpRuntime(deps) {
  const {
    RC_SUCCESS,
    allocHandle,
    readHandle,
    writeOut,
    intValue = null,
    stringValue,
    listItems,
    tuple2 = null,
    addOwner = null,
    newIntHandle,
    newStringHandle,
    newList,
    invokeClosure,
    retain = null,
    release = null,
    unitHandle = 0,
    TAG_RECORD,
    TAG_LIST,
    TAG_STRING,
    TAG_INT,
    TAG_CMD,
    TAG_TUPLE2,
    TAG_BYTES,
    TAG_MAYBE,
    TAG_FLOAT,
    TAG_CLOSURE = 5,
    TAG_RESULT = 8,
    constructorTags = {},
    resultOk = null,
    resultErr = null,
    jsonDecodeHelp = null,
    jsonDecodeErrorToString = null,
    bytesDecodeValue = null,
    fetchFn = typeof fetch !== "undefined" ? fetch.bind(globalThis) : null,
  } = deps;

  /** @type {((msg: number) => void) | null} */
  let dispatchMsg = null;

  /** @type {Map<string, AbortController>} */
  const inflightByTracker = new Map();

  /** @type {Map<string, { toMsgPtr: number, taggers: number[] }>} */
  const progressListeners = new Map();

  // Official elm/http `Response body` constructors are `BadUrl_` / `GoodStatus_`
  // (trailing underscore) so they do not collide with `Http.Error`.
  const httpResponseTag = (name, fallback) =>
    constructorTags[`Http.${name}`] ??
    constructorTags[`Http.${name}_`] ??
    constructorTags[name] ??
    constructorTags[`${name}_`] ??
    fallback;

  const RESP_BAD_URL = httpResponseTag("BadUrl", 1);
  const RESP_TIMEOUT = httpResponseTag("Timeout", 2);
  const RESP_NETWORK = httpResponseTag("NetworkError", 3);
  const RESP_BAD_STATUS = httpResponseTag("BadStatus", 4);
  const RESP_GOOD_STATUS = httpResponseTag("GoodStatus", 5);

  const EXPECT_STRING = "string";
  const EXPECT_JSON = "json";
  const EXPECT_BYTES = "bytes";
  const EXPECT_WHATEVER = "whatever";
  const EXPECT_STRING_RESPONSE = "string_response";
  const EXPECT_BYTES_RESPONSE = "bytes_response";
  const EXPECT_STRING_RESOLVER = "string_resolver";
  const EXPECT_BYTES_RESOLVER = "bytes_resolver";


  const HTTP_METHODS = new Set(["GET", "POST", "PUT", "DELETE", "HEAD", "PATCH", "OPTIONS"]);

  const setDispatchMsg = (fn) => {
    dispatchMsg = typeof fn === "function" ? fn : null;
  };

  const recordFields = (ptr) => readHandle(ptr)?.fields ?? [];

  const writeBodyRecord = (outPtr, kind, extra = {}) => {
    writeOut(
      outPtr,
      allocHandle({
        tag: TAG_RECORD,
        httpBodyKind: kind,
        fields: [],
        ...extra,
      })
    );
    return RC_SUCCESS;
  };

  const httpEmptyBody = (_outPtr, _reqPtr) => writeBodyRecord(_outPtr, "empty");

  const httpPair = (outPtr, keyPtr, valuePtr) => {
    if (typeof tuple2 === "function") {
      return tuple2(outPtr, keyPtr | 0, valuePtr | 0);
    }
    const first = keyPtr | 0;
    const second = valuePtr | 0;
    if (retain) {
      if (first) retain(null, first);
      if (second) retain(null, second);
    }
    const handle = allocHandle({ tag: TAG_TUPLE2, first, second });
    if (addOwner) {
      if (first) addOwner(first, handle);
      if (second) addOwner(second, handle);
    }
    writeOut(outPtr, handle);
    return RC_SUCCESS;
  };

  const bytesPayloadToUint8 = (bytesPtr) => {
    const payload = readHandle(bytesPtr | 0);
    if (payload?.tag === TAG_BYTES && payload.view) {
      return new Uint8Array(
        payload.view.buffer,
        payload.view.byteOffset,
        payload.view.byteLength
      );
    }
    if (payload?.tag === TAG_STRING) {
      return new TextEncoder().encode(payload.value ?? "");
    }
    return new Uint8Array(0);
  };

  const httpBytesToBlob = (outPtr, mimePtr, bytesPtr) => {
    const mime = stringValue(mimePtr | 0) || "application/octet-stream";
    const blob = new Blob([bytesPayloadToUint8(bytesPtr | 0)], { type: mime });
    return writeBodyRecord(outPtr, "blob", { blob });
  };

  const appendFormPart = (form, name, valuePtr) => {
    const payload = readHandle(valuePtr | 0);
    if (payload?.nativeFile) {
      form.append(name, payload.nativeFile);
      return;
    }
    if (payload?.httpBodyKind === "blob" && payload.blob) {
      form.append(name, payload.blob);
      return;
    }
    if (payload?.blob) {
      form.append(name, payload.blob);
      return;
    }
    if (payload?.tag === TAG_BYTES && payload.view) {
      form.append(name, new Blob([bytesPayloadToUint8(valuePtr | 0)]));
      return;
    }
    form.append(name, stringValue(valuePtr | 0));
  };

  const formDataHandle = (partsPtr) => {
    const form = typeof FormData !== "undefined" ? new FormData() : null;
    if (form) {
      for (const partPtr of listItems(partsPtr | 0)) {
        const part = readHandle(partPtr | 0);
        if (part?.tag !== TAG_TUPLE2) continue;
        appendFormPart(form, stringValue(part.first | 0), part.second | 0);
      }
    }
    return allocHandle({
      tag: TAG_RECORD,
      httpBodyKind: "form",
      formData: form,
      fields: [],
    });
  };

  const httpToFormData = (outPtr, partsPtr) => {
    writeOut(outPtr, formDataHandle(partsPtr));
    return RC_SUCCESS;
  };

  const httpFileBody = (outPtr, filePtr) =>
    httpPair(outPtr, newStringHandle(""), filePtr | 0);

  const httpMultipartBody = (outPtr, partsPtr) =>
    httpPair(outPtr, newStringHandle(""), formDataHandle(partsPtr));

  const httpBytesPart = (outPtr, keyPtr, mimePtr, bytesPtr) => {
    const mime = stringValue(mimePtr | 0) || "application/octet-stream";
    const blob = new Blob([bytesPayloadToUint8(bytesPtr | 0)], { type: mime });
    return httpPair(
      outPtr,
      keyPtr | 0,
      allocHandle({ tag: TAG_RECORD, httpBodyKind: "blob", blob, fields: [] })
    );
  };

  const httpToDataView = (outPtr, bodyPtr) => {
    writeOut(outPtr, bodyPtr | 0);
    return RC_SUCCESS;
  };

  const retainFields = (fields) => {
    const normalized = fields.map((f) => f | 0);
    if (retain) {
      for (const field of normalized) {
        if (field) retain(null, field);
      }
    }
    return normalized;
  };

  const httpExpect = (outPtr, toMsgPtr, decoderPtr, reqPtr) => {
    const handle = allocHandle({
      tag: TAG_RECORD,
      fields: retainFields([toMsgPtr | 0, decoderPtr | 0, reqPtr | 0]),
    });
    writeOut(outPtr, handle);
    return RC_SUCCESS;
  };

  const writeExpectRecord = (outPtr, kind, fields) => {
    writeOut(
      outPtr,
      allocHandle({
        tag: TAG_RECORD,
        httpExpectKind: kind,
        fields: retainFields(fields),
      })
    );
    return RC_SUCCESS;
  };

  const httpExpectString = (outPtr, toMsgPtr) =>
    writeExpectRecord(outPtr, EXPECT_STRING, [toMsgPtr | 0]);

  const httpExpectJson = (outPtr, toMsgPtr, decoderPtr) =>
    writeExpectRecord(outPtr, EXPECT_JSON, [toMsgPtr | 0, decoderPtr | 0]);

  const httpExpectBytes = (outPtr, toMsgPtr, decoderPtr) =>
    writeExpectRecord(outPtr, EXPECT_BYTES, [toMsgPtr | 0, decoderPtr | 0]);

  const httpExpectWhatever = (outPtr, toMsgPtr) =>
    writeExpectRecord(outPtr, EXPECT_WHATEVER, [toMsgPtr | 0]);

  const httpExpectStringResponse = (outPtr, toMsgPtr, toResultPtr) =>
    writeExpectRecord(outPtr, EXPECT_STRING_RESPONSE, [toMsgPtr | 0, toResultPtr | 0]);

  const httpExpectBytesResponse = (outPtr, toMsgPtr, toResultPtr) =>
    writeExpectRecord(outPtr, EXPECT_BYTES_RESPONSE, [toMsgPtr | 0, toResultPtr | 0]);

  const httpStringResolver = (outPtr, toResultPtr) =>
    writeExpectRecord(outPtr, EXPECT_STRING_RESOLVER, [toResultPtr | 0]);

  const httpBytesResolver = (outPtr, toResultPtr) =>
    writeExpectRecord(outPtr, EXPECT_BYTES_RESOLVER, [toResultPtr | 0]);

  const httpTask = (outPtr, reqPtr, risky = false) => {
    if (retain) retain(null, reqPtr | 0);
    writeOut(
      outPtr,
      allocHandle({
        tag: TAG_RESULT,
        isOk: true,
        taskKind: TASK_HTTP_ELM,
        value: reqPtr | 0,
        risky: !!risky,
      })
    );
    return RC_SUCCESS;
  };

  const httpRiskyTask = (outPtr, reqPtr) => httpTask(outPtr, reqPtr, true);

  const httpCommand = (outPtr, reqPtr, risky = false) => {
    const payload = readHandle(reqPtr | 0);
    if (payload?.tag === TAG_TUPLE2) {
      const tagPayload = readHandle(payload.first | 0);
      const tag = tagPayload?.tag === TAG_INT ? tagPayload.value | 0 : -1;
      if (tag === 1) {
        return httpCancel(outPtr, payload.second | 0);
      }
    }

    if (retain) retain(null, reqPtr | 0);
    const handle = allocHandle({
      tag: TAG_CMD,
      kind: "http",
      request: reqPtr | 0,
      risky: !!risky,
    });
    writeOut(outPtr, handle);
    return RC_SUCCESS;
  };

  const httpRiskyCommand = (outPtr, reqPtr) => httpCommand(outPtr, reqPtr, true);

  const httpCancel = (outPtr, trackerPtr) => {
    const tracker = stringValue(trackerPtr | 0);
    const controller = tracker ? inflightByTracker.get(tracker) : null;
    if (controller) {
      controller.abort();
      inflightByTracker.delete(tracker);
    }
    writeOut(outPtr, allocHandle({ tag: TAG_CMD, kind: "http_cancel", tracker: trackerPtr | 0 }));
    return RC_SUCCESS;
  };

  const registerProgressListener = (tracker, toMsgPtr, taggers = []) => {
    if (!tracker) return;
    unregisterProgressListener(tracker);
    const retainedTaggers = taggers.map((p) => p | 0);
    if (retain) {
      if (toMsgPtr) retain(null, toMsgPtr | 0);
      for (const tagger of retainedTaggers) {
        if (tagger) retain(null, tagger);
      }
    }
    progressListeners.set(tracker, {
      toMsgPtr: toMsgPtr | 0,
      taggers: retainedTaggers,
    });
  };

  const unregisterProgressListener = (tracker) => {
    if (!tracker) return;
    const prev = progressListeners.get(tracker);
    if (prev && release) {
      if (prev.toMsgPtr) release(prev.toMsgPtr | 0);
      for (const tagger of prev.taggers ?? []) {
        if (tagger) release(tagger | 0);
      }
    }
    progressListeners.delete(tracker);
  };

  const newFloatHandle = (value) => allocHandle({ tag: TAG_FLOAT, value: Number(value) || 0 });

  const maybeIntField = (value) => {
    if (value == null || Number.isNaN(value)) {
      return allocHandle({
        tag: TAG_MAYBE,
        value: null,
        ctorTag: constructorTags["Maybe.Nothing"] ?? constructorTags["Nothing"] ?? 2,
      });
    }

    return allocHandle({
      tag: TAG_MAYBE,
      value: newIntHandle(value | 0),
      isJust: true,
      ctorTag: constructorTags["Maybe.Just"] ?? constructorTags["Just"] ?? 1,
    });
  };

  // Http.Progress is 1-based declaration order (Sending=1, Receiving=2), same
  // as Result.Ok/Err. Fallbacks must match even when constructorTags is empty.
  const progressCtorTag = (name, fallback) =>
    constructorTags[`Http.${name}`] ??
    constructorTags[`Http.Progress.${name}`] ??
    constructorTags[name] ??
    fallback;

  const makeProgressUnion = (name, fallback, recordPtr) =>
    allocHandle({
      tag: TAG_TUPLE2,
      first: newIntHandle(progressCtorTag(name, fallback)),
      second: recordPtr | 0,
    });

  const makeSendingProgress = (sent, size) =>
    makeProgressUnion(
      "Sending",
      1,
      allocHandle({
        tag: TAG_RECORD,
        fields: [newIntHandle(sent | 0), newIntHandle(size | 0)],
      })
    );

  const makeReceivingProgress = (received, size) =>
    makeProgressUnion(
      "Receiving",
      2,
      allocHandle({
        tag: TAG_RECORD,
        fields: [newIntHandle(received | 0), maybeIntField(size)],
      })
    );

  const recordIntField = (recPtr, index) => {
    const rec = readHandle(recPtr | 0);
    const field = readHandle(rec?.fields?.[index] | 0);
    if (field?.tag === TAG_INT) return field.value | 0;
    if (field?.tag === TAG_FLOAT) return Math.floor(field.value) | 0;
    return 0;
  };

  const clamp01 = (value) => Math.min(1, Math.max(0, value));

  const httpFractionSent = (outPtr, recPtr) => {
    const size = recordIntField(recPtr, 1);
    const frac = size === 0 ? 1 : clamp01(recordIntField(recPtr, 0) / size);
    writeOut(outPtr, newFloatHandle(frac));
    return RC_SUCCESS;
  };

  const httpFractionReceived = (outPtr, recPtr) => {
    const rec = readHandle(recPtr | 0);
    const sizeMaybe = readHandle(rec?.fields?.[1] | 0);
    const unknown =
      !sizeMaybe || sizeMaybe.tag !== TAG_MAYBE || sizeMaybe.value == null || !sizeMaybe.isJust;
    if (unknown) {
      writeOut(outPtr, newFloatHandle(0));
      return RC_SUCCESS;
    }
    const nPayload = readHandle(sizeMaybe.value | 0);
    const n =
      nPayload?.tag === TAG_INT
        ? nPayload.value | 0
        : nPayload?.tag === TAG_FLOAT
          ? Math.floor(nPayload.value) | 0
          : 0;
    const frac = n === 0 ? 1 : clamp01(recordIntField(recPtr, 0) / n);
    writeOut(outPtr, newFloatHandle(frac));
    return RC_SUCCESS;
  };

  const dispatchProgress = (tracker, kind, loaded, size) => {
    const listener = tracker ? progressListeners.get(tracker) : null;
    if (!listener || !dispatchMsg) return;

    const progressPtr =
      kind === "sending"
        ? makeSendingProgress(loaded, size || 0)
        : makeReceivingProgress(loaded, size);
    let msgPtr = progressPtr;
    for (const taggerPtr of [...listener.taggers].reverse()) {
      const next = invokeClosure(taggerPtr, [msgPtr | 0]);
      if (msgPtr !== progressPtr && release) release(msgPtr | 0);
      if (next.rc !== RC_SUCCESS) return;
      msgPtr = next.value | 0;
    }

    const { rc, value: msg } = invokeClosure(listener.toMsgPtr, [msgPtr | 0]);
    if (release && msgPtr) release(msgPtr | 0);
    if (rc === RC_SUCCESS && msg) dispatchMsg(msg);
  };

  const unwrapRequestRecord = (ptr) => {
    const payload = readHandle(ptr);
    if (!payload) return null;
    if (payload.tag === TAG_RECORD) return payload;
    if (payload.tag === TAG_TUPLE2) {
      for (const child of [payload.first, payload.second]) {
        const inner = readHandle(child | 0);
        if (inner?.tag === TAG_RECORD) return inner;
      }
    }
    return null;
  };

  const methodFromFields = (fields) => {
    for (const ptr of fields) {
      const value = stringValue(ptr | 0);
      if (HTTP_METHODS.has(value)) return value;
    }
    return "";
  };

  const urlFromFields = (fields) => {
    for (const ptr of fields) {
      const value = stringValue(ptr | 0);
      if (value.startsWith("http://") || value.startsWith("https://") || value.startsWith("/")) {
        return value;
      }
    }
    for (const ptr of fields) {
      const payload = readHandle(ptr | 0);
      if (payload?.tag === TAG_CLOSURE && Array.isArray(payload.captures)) {
        for (const cap of payload.captures) {
          const value = stringValue(cap | 0);
          if (value.startsWith("http://") || value.startsWith("https://") || value.startsWith("/")) {
            return value;
          }
        }
      }
    }
    return "";
  };

  const headersFromFields = (fields) => {
    for (const ptr of fields) {
      const payload = readHandle(ptr | 0);
      if (payload?.tag === TAG_LIST) return listItems(ptr | 0);
    }
    return [];
  };

  const isHttpUrlString = (value) =>
    value.startsWith("http://") || value.startsWith("https://") || value.startsWith("/");

  const isBodyPair = (payload) => {
    if (payload?.tag !== TAG_TUPLE2) return false;
    const second = readHandle(payload.second | 0);
    if (
      second?.nativeFile ||
      second?.httpBodyKind ||
      second?.blob ||
      second?.tag === TAG_BYTES ||
      second?.formData
    ) {
      return true;
    }
    const mime = stringValue(payload.first | 0);
    return mime === "" || mime.includes("/");
  };

  const bodyFromFields = (fields) => {
    for (const ptr of fields) {
      const payload = readHandle(ptr | 0);
      if (payload?.httpBodyKind) return ptr | 0;
    }
    for (const ptr of fields) {
      if (isBodyPair(readHandle(ptr | 0))) return ptr | 0;
    }
    for (const ptr of fields) {
      const payload = readHandle(ptr | 0);
      if (payload?.tag === TAG_BYTES) return ptr | 0;
      if (payload?.tag === TAG_STRING) {
        const text = stringValue(ptr | 0);
        if (text && !isHttpUrlString(text) && !HTTP_METHODS.has(text)) return ptr | 0;
      }
    }
    return 0;
  };

  const bodyInitFromPtr = (bodyPtr, bytesRuntime) => {
    const payload = readHandle(bodyPtr | 0);
    if (!payload || payload.httpBodyKind === "empty") return { bodyInit: undefined, mime: "" };
    if (payload.httpBodyKind === "form") return { bodyInit: payload.formData, mime: "" };
    if (payload.httpBodyKind === "blob") return { bodyInit: payload.blob, mime: payload.blob?.type || "" };
    if (payload.nativeFile) return { bodyInit: payload.nativeFile, mime: payload.nativeFile.type || "" };
    if (payload.tag === TAG_TUPLE2) {
      const mime = stringValue(payload.first | 0);
      const inner = bodyInitFromPtr(payload.second | 0, bytesRuntime);
      if (inner.bodyInit !== undefined) {
        return { bodyInit: inner.bodyInit, mime: mime || inner.mime };
      }
      const second = readHandle(payload.second | 0);
      if (second?.tag === TAG_STRING) {
        return { bodyInit: second.value, mime };
      }
      return { bodyInit: undefined, mime };
    }
    if (payload.tag === TAG_STRING) return { bodyInit: payload.value, mime: "" };
    const bytes = bodyBytesFromPayload(bodyPtr | 0, bytesRuntime);
    if (bytes) return { bodyInit: bytes, mime: "" };
    return { bodyInit: undefined, mime: "" };
  };

  const expectCallbackFromFields = (fields) => {
    for (const ptr of fields) {
      const payload = readHandle(ptr | 0);
      if (payload?.httpExpectKind) return ptr | 0;
      if (payload?.tag === TAG_CLOSURE) return ptr | 0;
      if (payload?.tag === TAG_RECORD) {
        const expectFields = payload.fields ?? [];
        const third = expectFields[2] | 0;
        const second = expectFields[1] | 0;
        if (third) return third;
        if (second) return second;
      }
    }
    return 0;
  };

  const bytesExpectedFromFields = (fields) => {
    for (const ptr of fields) {
      const payload = readHandle(ptr | 0);
      if (
        payload?.httpExpectKind === EXPECT_BYTES ||
        payload?.httpExpectKind === EXPECT_WHATEVER ||
        payload?.httpExpectKind === EXPECT_BYTES_RESPONSE ||
        payload?.httpExpectKind === EXPECT_BYTES_RESOLVER
      ) {
        return true;
      }
      if (payload?.tag === TAG_RECORD) {
        const first = stringValue(payload.fields?.[0] | 0);
        if (first === "arraybuffer") return true;
      }
      if (stringValue(ptr | 0) === "arraybuffer") return true;
    }
    return false;
  };

  const timeoutFromFields = (fields) => {
    for (const ptr of fields) {
      const ms = readTimeoutMs(ptr | 0);
      if (ms > 0) return ms;
    }
    return 0;
  };

  const trackerFromFields = (fields) => {
    for (const ptr of fields) {
      const tracker = readTracker(ptr | 0);
      if (tracker) return tracker;
    }
    return null;
  };

  const headersFromResponse = (response) => {
    const pairs = [];
    if (response?.headers?.forEach) {
      response.headers.forEach((value, key) => {
        pairs.push(
          allocHandle({
            tag: TAG_TUPLE2,
            first: newStringHandle(key),
            second: newStringHandle(value),
          })
        );
      });
    }
    return newList(pairs);
  };

  const bodyBytesFromPayload = (bodyPtr, bytesRuntime) => {
    const bodyPayload = readHandle(bodyPtr);
    if (!bodyPayload) return null;
    if (bodyPayload.tag === TAG_STRING) {
      const encoded = new TextEncoder().encode(bodyPayload.value ?? "");
      return new Uint8Array(encoded);
    }
    if (bodyPayload.tag === TAG_BYTES && bodyPayload.view) {
      const copy = new Uint8Array(bodyPayload.view.byteLength);
      copy.set(
        new Uint8Array(bodyPayload.view.buffer, bodyPayload.view.byteOffset, bodyPayload.view.byteLength)
      );
      return copy;
    }
    if (bytesRuntime?.listToBytes) {
      const fromList = bytesRuntime.listToBytes(bodyPtr);
      if (fromList) return fromList;
    }
    return null;
  };

  const readTimeoutMs = (maybePtr) => {
    const payload = readHandle(maybePtr | 0);
    if (!payload || payload.tag !== TAG_MAYBE || payload.value == null) return 0;
    const inner = readHandle(payload.value | 0);
    if (!inner) return 0;
    if (inner.tag === TAG_FLOAT) return Math.max(0, Math.floor(inner.value));
    if (inner.tag === TAG_INT) return Math.max(0, inner.value | 0);
    return 0;
  };

  const readTracker = (maybePtr) => {
    const payload = readHandle(maybePtr | 0);
    if (!payload || payload.tag !== TAG_MAYBE || payload.value == null) return null;
    const tracker = stringValue(payload.value | 0);
    return tracker || null;
  };

  const makeMetadata = (url, status, statusText, headers) =>
    allocHandle({
      tag: TAG_RECORD,
      fields: [
        newStringHandle(url),
        newIntHandle(status | 0),
        newStringHandle(statusText || ""),
        headers,
      ],
    });

  const makeResponse = (tag, payloadPtr = 0) => {
    if (!payloadPtr) return newIntHandle(tag | 0);
    return allocHandle({
      tag: TAG_TUPLE2,
      first: newIntHandle(tag | 0),
      second: payloadPtr | 0,
    });
  };

  // Official: BadStatus Metadata | GoodStatus Metadata body.
  const makeStatusResponse = (tag, metadataPtr, bodyPtr) => {
    if (tag === RESP_GOOD_STATUS) {
      return makeResponse(
        tag,
        allocHandle({
          tag: TAG_TUPLE2,
          first: metadataPtr | 0,
          second: bodyPtr | 0,
        })
      );
    }
    return makeResponse(tag, metadataPtr | 0);
  };

  const httpErrorTag = (name, fallback) =>
    constructorTags[`Http.${name}`] ??
    constructorTags[`Http.Error.${name}`] ??
    constructorTags[name] ??
    fallback;

  const makeHttpError = (name, fallback, payloadPtr = 0) => {
    const tag = httpErrorTag(name, fallback);
    if (payloadPtr) {
      return allocHandle({
        tag: TAG_TUPLE2,
        first: newIntHandle(tag),
        second: payloadPtr | 0,
      });
    }
    return newIntHandle(tag);
  };

  const makeResultOk = (valuePtr) =>
    typeof resultOk === "function"
      ? resultOk(valuePtr | 0)
      : allocHandle({ tag: TAG_RESULT, isOk: true, value: valuePtr | 0 });

  const makeResultErr = (valuePtr) =>
    typeof resultErr === "function"
      ? resultErr(valuePtr | 0)
      : allocHandle({ tag: TAG_RESULT, isOk: false, value: valuePtr | 0 });

  const responseTag = (responsePtr) => {
    const payload = readHandle(responsePtr | 0);
    if (!payload) return -1;
    if (payload.tag === TAG_TUPLE2) {
      const tagPayload = readHandle(payload.first | 0);
      if (tagPayload?.tag === TAG_INT) return tagPayload.value | 0;
    }
    if (payload.tag === TAG_INT) return payload.value | 0;
    return -1;
  };

  const responsePayload = (responsePtr) => {
    const payload = readHandle(responsePtr | 0);
    if (payload?.tag === TAG_TUPLE2) return payload.second | 0;
    return 0;
  };

  const metadataStatusCode = (metadataPtr) => {
    const metadata = readHandle(metadataPtr | 0);
    const statusPtr = metadata?.fields?.[1] | 0;
    const status = readHandle(statusPtr);
    if (status?.tag === TAG_INT) return statusPtr;
    return newIntHandle(0);
  };

  const statusBody = (statusPayloadPtr) => {
    const pair = readHandle(statusPayloadPtr | 0);
    if (pair?.tag === TAG_TUPLE2) {
      return { metadata: pair.first | 0, body: pair.second | 0 };
    }
    return { metadata: statusPayloadPtr | 0, body: 0 };
  };

  const decodeJsonBody = (decoderPtr, bodyPtr) => {
    if (typeof jsonDecodeHelp !== "function") {
      return { ok: false, error: newStringHandle("JSON decode unavailable") };
    }
    let parsed;
    try {
      parsed = JSON.parse(stringValue(bodyPtr | 0));
    } catch (err) {
      return {
        ok: false,
        error: newStringHandle(`This is not valid JSON! ${err?.message ?? err}`),
      };
    }
    const step = jsonDecodeHelp(decoderPtr | 0, parsed);
    if (step?.ok) return { ok: true, value: step.handle | 0 };
    const errPtr = step?.error | 0;
    const text =
      typeof jsonDecodeErrorToString === "function" && errPtr
        ? jsonDecodeErrorToString(errPtr)
        : "JSON decode failed";
    return { ok: false, error: newStringHandle(text) };
  };

  const decodeBytesBody = (decoderPtr, bodyPtr) => {
    if (typeof bytesDecodeValue !== "function") return { ok: false };
    return bytesDecodeValue(decoderPtr | 0, bodyPtr | 0);
  };

  const resolveExpectBody = (kind, fields, bodyPtr) => {
    if (kind === EXPECT_STRING) return { ok: true, value: bodyPtr | 0 };
    if (kind === EXPECT_WHATEVER) return { ok: true, value: unitHandle | 0 };
    if (kind === EXPECT_JSON) return decodeJsonBody(fields[1] | 0, bodyPtr);
    if (kind === EXPECT_BYTES) {
      const step = decodeBytesBody(fields[1] | 0, bodyPtr);
      if (step?.ok) return { ok: true, value: step.value | 0 };
      return { ok: false, error: newStringHandle("unexpected bytes") };
    }
    return { ok: true, value: bodyPtr | 0 };
  };

  const resolveToResult = (callbackPtr, responsePtr) => {
    const expect = readHandle(callbackPtr | 0);
    const kind = expect?.httpExpectKind;
    const fields = expect?.fields ?? [];
    const tag = responseTag(responsePtr);
    const payloadPtr = responsePayload(responsePtr);

    if (tag === RESP_BAD_URL) {
      return makeResultErr(makeHttpError("BadUrl", 0, payloadPtr || newStringHandle("")));
    }
    if (tag === RESP_TIMEOUT) {
      return makeResultErr(makeHttpError("Timeout", 1));
    }
    if (tag === RESP_NETWORK) {
      return makeResultErr(makeHttpError("NetworkError", 2));
    }
    if (tag === RESP_BAD_STATUS) {
      const { metadata } = statusBody(payloadPtr);
      return makeResultErr(makeHttpError("BadStatus", 3, metadataStatusCode(metadata)));
    }
    if (tag === RESP_GOOD_STATUS) {
      const { body } = statusBody(payloadPtr);
      const inner = resolveExpectBody(kind, fields, body);
      if (inner.ok) return makeResultOk(inner.value);
      return makeResultErr(makeHttpError("BadBody", 4, inner.error | 0));
    }
    return makeResultErr(makeHttpError("NetworkError", 2));
  };

  const expectMapTaggers = (expect) => {
    if (Array.isArray(expect?.mapTaggers)) return expect.mapTaggers;
    const n = expect?.mapTaggerCount | 0;
    if (n > 0 && Array.isArray(expect?.fields)) {
      return expect.fields.slice(-n);
    }
    return [];
  };

  // Official mapExpect is `func << expect.toValue`. Cmd.map wrappers collected
  // outer-first as [innerFn, ...outerFns] so left-to-right is outer(inner(msg)).
  const dispatchWithTaggers = (msgPtr, taggers) => {
    let ptr = msgPtr | 0;
    for (const taggerPtr of taggers ?? []) {
      if (!taggerPtr) continue;
      const next = invokeClosure(taggerPtr | 0, [ptr]);
      if (next.rc !== RC_SUCCESS) return;
      ptr = next.value | 0;
    }
    if (ptr && dispatchMsg) dispatchMsg(ptr);
  };

  const dispatchResponse = (callbackPtr, responsePtr, cmdTaggers = []) => {
    if (!callbackPtr || !dispatchMsg) return;
    const expect = readHandle(callbackPtr | 0);
    const taggers = [...expectMapTaggers(expect), ...(cmdTaggers ?? [])];
    if (expect?.httpExpectKind === EXPECT_STRING_RESPONSE || expect?.httpExpectKind === EXPECT_BYTES_RESPONSE) {
      const toResult = expect.fields?.[1] | 0;
      const toMsg = expect.fields?.[0] | 0;
      const mapped = invokeClosure(toResult, [responsePtr | 0]);
      if (mapped.rc !== RC_SUCCESS) return;
      const { rc, value: msg } = invokeClosure(toMsg, [mapped.value | 0]);
      if (rc === RC_SUCCESS && msg) dispatchWithTaggers(msg, taggers);
      return;
    }
    if (expect?.httpExpectKind) {
      const resultPtr = resolveToResult(callbackPtr, responsePtr);
      const toMsg = expect.fields?.[0] | 0;
      const { rc, value: msg } = invokeClosure(toMsg, [resultPtr | 0]);
      if (rc === RC_SUCCESS && msg) dispatchWithTaggers(msg, taggers);
      return;
    }
    const { rc, value: msg } = invokeClosure(callbackPtr, [responsePtr | 0]);
    if (rc === RC_SUCCESS && msg) {
      dispatchWithTaggers(msg, taggers);
    }
  };

  const httpMapExpect = (outPtr, funcPtr, expectPtr) => {
    const expect = readHandle(expectPtr | 0);
    if (!expect) {
      writeOut(outPtr, 0);
      return RC_SUCCESS;
    }
    const prev = expectMapTaggers(expect);
    const fields = [...(expect.fields ?? [])];
    if (funcPtr) fields.push(funcPtr | 0);
    writeOut(
      outPtr,
      allocHandle({
        tag: TAG_RECORD,
        httpExpectKind: expect.httpExpectKind,
        fields: retainFields(fields),
        mapTaggers: [...prev, funcPtr | 0],
        mapTaggerCount: prev.length + 1,
      })
    );
    return RC_SUCCESS;
  };

  const runHttpRequestXhr = async ({
    method,
    url,
    headers,
    bodyInit,
    callback,
    bytesExpected,
    bytesRuntime,
    tracker,
    controller,
    timeoutMs,
    timeoutId,
    reqPtr,
    risky,
    deliver = dispatchResponse,
  }) => {
    await new Promise((resolve) => {
      const xhr = new XMLHttpRequest();
      xhr.open(method, url);
      xhr.withCredentials = !!risky;
      for (const [key, value] of headers.entries()) {
        xhr.setRequestHeader(key, value);
      }
      if (controller) {
        controller.signal.addEventListener("abort", () => xhr.abort());
      }

      xhr.upload.addEventListener("progress", (event) => {
        dispatchProgress(
          tracker,
          "sending",
          event.loaded,
          event.lengthComputable ? event.total : 0
        );
      });

      xhr.addEventListener("progress", (event) => {
        dispatchProgress(
          tracker,
          "receiving",
          event.loaded,
          event.lengthComputable ? event.total : null
        );
      });

      xhr.addEventListener("loadend", async () => {
        if (timeoutId) clearTimeout(timeoutId);
        if (tracker) inflightByTracker.delete(tracker);

        try {
          if (xhr.status === 0) {
            deliver(callback, makeResponse(RESP_NETWORK));
            resolve();
            return;
          }

          const responseHeaders = new Headers();
          const raw = xhr.getAllResponseHeaders?.() ?? "";
          for (const line of raw.trim().split(/[\r\n]+/)) {
            const idx = line.indexOf(":");
            if (idx > 0) {
              responseHeaders.append(line.slice(0, idx).trim(), line.slice(idx + 1).trim());
            }
          }

          const contentType = responseHeaders.get("content-type") ?? "";
          const useBytes =
            bytesExpected ||
            contentType.includes("octet-stream") ||
            contentType.includes("application/pdf");

          let bodyField;
          if (useBytes) {
            const view = new DataView(xhr.response);
            bodyField =
              bytesRuntime?.newBytesHandle?.(view) ??
              newStringHandle(new TextDecoder().decode(xhr.response));
          } else {
            bodyField = newStringHandle(xhr.responseText ?? "");
          }

          const headerList = headersFromResponse({ headers: responseHeaders });
          const metadata = makeMetadata(url, xhr.status, xhr.statusText || "", headerList);
          const status = xhr.status | 0;
          const responseUnion =
            status >= 200 && status <= 299
              ? makeStatusResponse(RESP_GOOD_STATUS, metadata, bodyField)
              : makeStatusResponse(RESP_BAD_STATUS, metadata, bodyField);

          deliver(callback, responseUnion);
        } catch (_err) {
          deliver(callback, makeResponse(RESP_NETWORK));
        } finally {
          if (release) release(reqPtr | 0);
          resolve();
        }
      });

      xhr.addEventListener("error", () => {
        if (timeoutId) clearTimeout(timeoutId);
        if (tracker) inflightByTracker.delete(tracker);
        deliver(callback, makeResponse(RESP_NETWORK));
        if (release) release(reqPtr | 0);
        resolve();
      });

      xhr.addEventListener("abort", () => {
        if (timeoutId) clearTimeout(timeoutId);
        if (tracker) inflightByTracker.delete(tracker);
        deliver(callback, makeResponse(RESP_TIMEOUT));
        if (release) release(reqPtr | 0);
        resolve();
      });

      xhr.responseType = bytesExpected ? "arraybuffer" : "text";
      xhr.send(bodyInit ?? null);
    });
  };

  const runHttpRequest = async (
    reqPtr,
    bytesRuntime = null,
    risky = false,
    deliver = dispatchResponse,
    processController = null
  ) => {
    if (!fetchFn) return;
    if (deliver === dispatchResponse && !dispatchMsg) return;

    const reqPayload = unwrapRequestRecord(reqPtr);
    if (!reqPayload) return;

    const fields = reqPayload.fields ?? [];
    let url = urlFromFields(fields);
    const headersList = headersFromFields(fields);
    const body = bodyFromFields(fields);
    const method = methodFromFields(fields) || (body ? "POST" : "GET");
    const callback = expectCallbackFromFields(fields);
    const bytesExpected = bytesExpectedFromFields(fields);
    const timeoutMs = timeoutFromFields(fields);
    const tracker = trackerFromFields(fields);

    if (!url) {
      deliver(callback, makeResponse(RESP_BAD_URL, newStringHandle("")));
      return;
    }

    if (!callback) return;

    const headers = new Headers();
    for (const pairPtr of headersList) {
      const pair = readHandle(pairPtr);
      if (pair?.tag === TAG_TUPLE2) {
        headers.append(stringValue(pair.first | 0), stringValue(pair.second | 0));
      }
    }

    const { bodyInit, mime } = bodyInitFromPtr(body, bytesRuntime);
    if (mime && !headers.has("Content-Type") && !(typeof FormData !== "undefined" && bodyInit instanceof FormData)) {
      headers.set("Content-Type", mime);
    }

    const controller =
      processController ||
      (typeof AbortController !== "undefined" ? new AbortController() : null);
    if (tracker && controller) {
      inflightByTracker.set(tracker, controller);
    }
    let timeoutId = null;
    if (controller && timeoutMs > 0) {
      timeoutId = setTimeout(() => controller.abort(), timeoutMs);
    }

    if (tracker && progressListeners.has(tracker) && typeof XMLHttpRequest !== "undefined") {
      await runHttpRequestXhr({
        method,
        url,
        headers,
        bodyInit,
        callback,
        bytesExpected,
        bytesRuntime,
        tracker,
        controller,
        timeoutMs,
        timeoutId,
        reqPtr,
        risky,
        deliver,
      });
      return;
    }

    try {
      const response = await fetchFn(url, {
        method,
        headers,
        body: bodyInit,
        signal: controller?.signal,
        credentials: risky ? "include" : "same-origin",
      });
      if (timeoutId) clearTimeout(timeoutId);
      if (tracker) inflightByTracker.delete(tracker);

      const responseHeaders = headersFromResponse(response);
      const contentType = response.headers?.get?.("content-type") ?? "";
      const useBytes =
        bytesExpected ||
        contentType.includes("octet-stream") ||
        contentType.includes("application/pdf");

      let bodyField;
      if (useBytes) {
        const arrayBuffer = await response.arrayBuffer();
        const view = new DataView(arrayBuffer);
        bodyField =
          bytesRuntime?.newBytesHandle?.(view) ??
          newStringHandle(new TextDecoder().decode(arrayBuffer));
      } else {
        const text = await response.text();
        bodyField = newStringHandle(text);
      }

      const metadata = makeMetadata(
        response.url || url,
        response.status,
        response.statusText || "",
        responseHeaders
      );
      const status = response.status | 0;
      const responseUnion =
        status >= 200 && status <= 299
          ? makeStatusResponse(RESP_GOOD_STATUS, metadata, bodyField)
          : makeStatusResponse(RESP_BAD_STATUS, metadata, bodyField);

      deliver(callback, responseUnion);
    } catch (err) {
      if (timeoutId) clearTimeout(timeoutId);
      if (tracker) inflightByTracker.delete(tracker);
      const isTimeout = err?.name === "AbortError";
      deliver(
        callback,
        makeResponse(isTimeout ? RESP_TIMEOUT : RESP_NETWORK)
      );
    } finally {
      if (release) release(reqPtr | 0);
    }
  };

  const resolverToResultPtr = (callbackPtr, responsePtr) => {
    const expect = readHandle(callbackPtr | 0);
    if (
      expect?.httpExpectKind === EXPECT_STRING_RESOLVER ||
      expect?.httpExpectKind === EXPECT_BYTES_RESOLVER
    ) {
      const mapped = invokeClosure(expect.fields?.[0] | 0, [responsePtr | 0]);
      return mapped.value | 0;
    }
    if (
      expect?.httpExpectKind === EXPECT_STRING_RESPONSE ||
      expect?.httpExpectKind === EXPECT_BYTES_RESPONSE
    ) {
      const mapped = invokeClosure(expect.fields?.[1] | 0, [responsePtr | 0]);
      return mapped.value | 0;
    }
    if (expect?.httpExpectKind) {
      return resolveToResult(callbackPtr, responsePtr) | 0;
    }
    const mapped = invokeClosure(callbackPtr | 0, [responsePtr | 0]);
    return mapped.value | 0;
  };

  const resultCtorTag = (name, fallback) =>
    constructorTags[`Result.${name}`] ?? constructorTags[name] ?? fallback;

  const RESULT_OK = resultCtorTag("Ok", 1);
  const RESULT_ERR = resultCtorTag("Err", 2);

  const unionTag = (ptr) => {
    const payload = readHandle(ptr | 0);
    if (!payload) return -1;
    if (payload.ctorTag != null) return payload.ctorTag | 0;
    if (payload.tag === TAG_INT) return payload.value | 0;
    if (payload.tag === TAG_TUPLE2) {
      const first = readHandle(payload.first | 0);
      if (first?.tag === TAG_INT) return first.value | 0;
      return typeof intValue === "function" ? intValue(payload.first | 0) : -1;
    }
    return typeof intValue === "function" ? intValue(ptr | 0) : -1;
  };

  // Official Resolver `toResult` returns Elm `Result x a` (`Ok` / `Err`
  // constructors). Host `TAG_RESULT` is the Task stepper's completed shape.
  const peelResolverResult = (resultPtr) => {
    const payload = readHandle(resultPtr | 0);
    if (!payload) return null;
    if (payload.tag === TAG_RESULT && payload.taskKind == null) {
      return { isOk: !!payload.isOk, value: payload.value | 0 };
    }
    if (payload.tag === TAG_TUPLE2) {
      const tag = unionTag(resultPtr);
      if (tag === RESULT_OK) return { isOk: true, value: payload.second | 0 };
      if (tag === RESULT_ERR) return { isOk: false, value: payload.second | 0 };
    }
    return null;
  };

  const resultPtrToForced = (resultPtr) => {
    const peeled = peelResolverResult(resultPtr);
    if (peeled) {
      return {
        rc: RC_SUCCESS,
        value: allocHandle({
          tag: TAG_RESULT,
          isOk: peeled.isOk,
          value: peeled.value | 0,
        }),
      };
    }
    return {
      rc: RC_SUCCESS,
      value: allocHandle({ tag: TAG_RESULT, isOk: true, value: resultPtr | 0 }),
    };
  };

  const runHttpRequestAsTask = async (taskPtr, bytesRuntime = null, processController = null) => {
    const payload = readHandle(taskPtr | 0);
    const reqPtr = payload?.value | 0;
    const risky = !!payload?.risky;
    let forced = {
      rc: RC_SUCCESS,
      value: allocHandle({
        tag: TAG_RESULT,
        isOk: false,
        value: newStringHandle("Http.task"),
      }),
    };
    const deliver = (callbackPtr, responsePtr) => {
      try {
        forced = resultPtrToForced(resolverToResultPtr(callbackPtr, responsePtr));
      } catch (err) {
        forced = {
          rc: RC_SUCCESS,
          value: allocHandle({
            tag: TAG_RESULT,
            isOk: false,
            value: newStringHandle(String(err?.message || "Http.task")),
          }),
        };
      }
    };
    await runHttpRequest(reqPtr, bytesRuntime, risky, deliver, processController);
    return forced;
  };

  const drainHttpCommands = async (cmdPtr, bytesRuntime = null, taggers = []) => {
    const payload = readHandle(cmdPtr);
    if (!payload) return;
    if (payload.tag === TAG_CMD && payload.kind === "http") {
      const deliver = (callbackPtr, responsePtr) =>
        dispatchResponse(callbackPtr, responsePtr, taggers);
      await runHttpRequest(payload.request | 0, bytesRuntime, !!payload.risky, deliver);
      return;
    }
    if (payload.tag === TAG_CMD && payload.kind === "http_cancel") {
      const tracker = stringValue(payload.tracker | 0);
      const controller = tracker ? inflightByTracker.get(tracker) : null;
      if (controller) {
        controller.abort();
        inflightByTracker.delete(tracker);
      }
      return;
    }
    if (payload.tag === TAG_CMD && payload.kind === "batch" && Array.isArray(payload.items)) {
      await Promise.all(
        payload.items.map((item) => drainHttpCommands(item | 0, bytesRuntime, taggers))
      );
    }
  };

  return {
    setDispatchMsg,
    drainHttpCommands,
    runHttpRequest,
    httpEmptyBody,
    httpPair,
    httpFileBody,
    httpMultipartBody,
    httpBytesPart,
    httpToFormData,
    httpBytesToBlob,
    httpToDataView,
    httpExpect,
    httpMapExpect,
    httpExpectString,
    httpExpectJson,
    httpExpectBytes,
    httpExpectWhatever,
    httpExpectStringResponse,
    httpExpectBytesResponse,
    httpStringResolver,
    httpBytesResolver,
    httpCommand,
    httpRiskyCommand,
    httpTask,
    httpRiskyTask,
    httpCancel,
    httpFractionSent,
    httpFractionReceived,
    runHttpRequestAsTask,
    registerProgressListener,
    unregisterProgressListener,
  };
}
