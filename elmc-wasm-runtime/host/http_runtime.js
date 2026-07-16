/**
 * Browser Http kernel runtime for elmc WASM web builds.
 */

export function createHttpRuntime(deps) {
  const {
    RC_SUCCESS,
    allocHandle,
    readHandle,
    writeOut,
    stringValue,
    listItems,
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
    fetchFn = typeof fetch !== "undefined" ? fetch.bind(globalThis) : null,
  } = deps;

  /** @type {((msg: number) => void) | null} */
  let dispatchMsg = null;

  /** @type {Map<string, AbortController>} */
  const inflightByTracker = new Map();

  /** @type {Map<string, { toMsgPtr: number, taggers: number[] }>} */
  const progressListeners = new Map();

  const RESP_BAD_URL = 0;
  const RESP_TIMEOUT = 1;
  const RESP_NETWORK = 2;
  const RESP_BAD_STATUS = 3;
  const RESP_GOOD_STATUS = 4;

  const HTTP_METHODS = new Set(["GET", "POST", "PUT", "DELETE", "HEAD", "PATCH", "OPTIONS"]);

  const setDispatchMsg = (fn) => {
    dispatchMsg = typeof fn === "function" ? fn : null;
  };

  const recordFields = (ptr) => readHandle(ptr)?.fields ?? [];

  const httpEmptyBody = (outPtr, reqPtr) => {
    writeOut(outPtr, reqPtr | 0);
    return RC_SUCCESS;
  };

  const httpPair = (outPtr, keyPtr, valuePtr) => {
    writeOut(
      outPtr,
      allocHandle({ tag: TAG_TUPLE2, first: keyPtr | 0, second: valuePtr | 0 })
    );
    return RC_SUCCESS;
  };

  const httpToDataView = (outPtr, bodyPtr) => {
    writeOut(outPtr, bodyPtr | 0);
    return RC_SUCCESS;
  };

  const httpExpect = (outPtr, toMsgPtr, decoderPtr, reqPtr) => {
    const handle = allocHandle({
      tag: TAG_RECORD,
      fields: [toMsgPtr | 0, decoderPtr | 0, reqPtr | 0],
    });
    writeOut(outPtr, handle);
    return RC_SUCCESS;
  };

  const httpCommand = (outPtr, reqPtr) => {
    const payload = readHandle(reqPtr | 0);
    if (payload?.tag === TAG_TUPLE2) {
      const tagPayload = readHandle(payload.first | 0);
      const tag = tagPayload?.tag === TAG_INT ? tagPayload.value | 0 : -1;
      if (tag === 1) {
        return httpCancel(outPtr, payload.second | 0);
      }
    }

    if (retain) retain(null, reqPtr | 0);
    const handle = allocHandle({ tag: TAG_CMD, kind: "http", request: reqPtr | 0 });
    writeOut(outPtr, handle);
    return RC_SUCCESS;
  };

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
    progressListeners.set(tracker, { toMsgPtr: toMsgPtr | 0, taggers: taggers.map((p) => p | 0) });
  };

  const unregisterProgressListener = (tracker) => {
    if (tracker) progressListeners.delete(tracker);
  };

  const newFloatHandle = (value) => allocHandle({ tag: TAG_FLOAT, value: Number(value) || 0 });

  const maybeFloatField = (value) => {
    if (value == null || Number.isNaN(value)) {
      return allocHandle({ tag: TAG_MAYBE, value: null });
    }

    return allocHandle({
      tag: TAG_MAYBE,
      value: newFloatHandle(value),
      isJust: true,
      ctorTag: 1,
    });
  };

  const makeProgressHandle = (received, size) =>
    allocHandle({
      tag: TAG_RECORD,
      fields: [newFloatHandle(received), maybeFloatField(size)],
    });

  const dispatchProgress = (tracker, received, size) => {
    const listener = tracker ? progressListeners.get(tracker) : null;
    if (!listener || !dispatchMsg) return;

    const progressPtr = makeProgressHandle(received, size);
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
    return "GET";
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

  const bodyFromFields = (fields) => {
    for (const ptr of fields) {
      const payload = readHandle(ptr | 0);
      if (payload?.tag === TAG_LIST || payload?.tag === TAG_STRING || payload?.tag === TAG_BYTES) {
        return ptr | 0;
      }
    }
    return 0;
  };

  const expectCallbackFromFields = (fields) => {
    for (const ptr of fields) {
      const payload = readHandle(ptr | 0);
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

  const makeResponse = (tag, payloadPtr) =>
    allocHandle({
      tag: TAG_TUPLE2,
      first: newIntHandle(tag | 0),
      second: payloadPtr | 0,
    });

  const makeStatusResponse = (tag, metadataPtr, bodyPtr) =>
    makeResponse(
      tag,
      allocHandle({
        tag: TAG_TUPLE2,
        first: metadataPtr | 0,
        second: bodyPtr | 0,
      })
    );

  const dispatchResponse = (callbackPtr, responsePtr) => {
    if (!callbackPtr) return;
    const { rc, value: msg } = invokeClosure(callbackPtr, [responsePtr | 0]);
    if (rc === RC_SUCCESS && msg) {
      dispatchMsg(msg);
    }
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
  }) => {
    await new Promise((resolve) => {
      const xhr = new XMLHttpRequest();
      xhr.open(method, url);
      for (const [key, value] of headers.entries()) {
        xhr.setRequestHeader(key, value);
      }
      if (controller) {
        controller.signal.addEventListener("abort", () => xhr.abort());
      }

      xhr.upload.addEventListener("progress", (event) => {
        if (!event.lengthComputable) return;
        dispatchProgress(tracker, event.loaded, event.total);
      });

      xhr.addEventListener("progress", (event) => {
        if (!event.lengthComputable) return;
        dispatchProgress(tracker, event.loaded, event.total);
      });

      xhr.addEventListener("loadend", async () => {
        if (timeoutId) clearTimeout(timeoutId);
        if (tracker) inflightByTracker.delete(tracker);

        try {
          if (xhr.status === 0) {
            dispatchResponse(callback, makeResponse(RESP_NETWORK, unitHandle | 0));
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

          dispatchResponse(callback, responseUnion);
        } catch (_err) {
          dispatchResponse(callback, makeResponse(RESP_NETWORK, unitHandle | 0));
        } finally {
          if (release) release(reqPtr | 0);
          resolve();
        }
      });

      xhr.addEventListener("error", () => {
        if (timeoutId) clearTimeout(timeoutId);
        if (tracker) inflightByTracker.delete(tracker);
        dispatchResponse(callback, makeResponse(RESP_NETWORK, unitHandle | 0));
        if (release) release(reqPtr | 0);
        resolve();
      });

      xhr.addEventListener("abort", () => {
        if (timeoutId) clearTimeout(timeoutId);
        if (tracker) inflightByTracker.delete(tracker);
        dispatchResponse(callback, makeResponse(RESP_TIMEOUT, unitHandle | 0));
        if (release) release(reqPtr | 0);
        resolve();
      });

      xhr.responseType = bytesExpected ? "arraybuffer" : "text";
      xhr.send(bodyInit ?? null);
    });
  };

  const runHttpRequest = async (reqPtr, bytesRuntime = null) => {
    if (!fetchFn || !dispatchMsg) return;

    const reqPayload = unwrapRequestRecord(reqPtr);
    if (!reqPayload) return;

    const fields = reqPayload.fields ?? [];
    const method = methodFromFields(fields);
    let url = urlFromFields(fields);
    const headersList = headersFromFields(fields);
    const body = bodyFromFields(fields);
    const callback = expectCallbackFromFields(fields);
    const bytesExpected = bytesExpectedFromFields(fields);
    const timeoutMs = timeoutFromFields(fields);
    const tracker = trackerFromFields(fields);

    if (!url) {
      dispatchResponse(callback, makeResponse(RESP_BAD_URL, newStringHandle("")));
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

    let bodyInit = undefined;
    const bodyBytes = bodyBytesFromPayload(body, bytesRuntime);
    if (bodyBytes) {
      bodyInit = bodyBytes;
    } else {
      const bodyPayload = readHandle(body);
      if (bodyPayload?.tag === TAG_STRING) {
        bodyInit = bodyPayload.value;
      }
    }

    const controller = typeof AbortController !== "undefined" ? new AbortController() : null;
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
      });
      return;
    }

    try {
      const response = await fetchFn(url, {
        method,
        headers,
        body: bodyInit,
        signal: controller?.signal,
      });
      if (timeoutId) clearTimeout(timeoutId);
      if (tracker) inflightByTracker.delete(tracker);

      const responseHeaders = headersFromResponse(response);
      const contentType = response.headers?.get?.("content-type") ?? "";
      const useBytes =
        bytesExpected ||
        contentType.includes("octet-stream") ||
        contentType.includes("application/pdf") ||
        bodyBytes != null;

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

      dispatchResponse(callback, responseUnion);
    } catch (err) {
      if (timeoutId) clearTimeout(timeoutId);
      if (tracker) inflightByTracker.delete(tracker);
      const isTimeout = err?.name === "AbortError";
      dispatchResponse(
        callback,
        makeResponse(isTimeout ? RESP_TIMEOUT : RESP_NETWORK, unitHandle | 0)
      );
    } finally {
      if (release) release(reqPtr | 0);
    }
  };

  const drainHttpCommands = async (cmdPtr, bytesRuntime = null) => {
    const payload = readHandle(cmdPtr);
    if (!payload) return;
    if (payload.tag === TAG_CMD && payload.kind === "http") {
      await runHttpRequest(payload.request | 0, bytesRuntime);
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
      for (const item of payload.items) {
        await drainHttpCommands(item | 0, bytesRuntime);
      }
    }
  };

  return {
    setDispatchMsg,
    drainHttpCommands,
    runHttpRequest,
    httpEmptyBody,
    httpPair,
    httpToDataView,
    httpExpect,
    httpCommand,
    httpCancel,
    registerProgressListener,
    unregisterProgressListener,
  };
}
