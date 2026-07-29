/**
 * Browser Task / Process runtime for elmc WASM web builds.
 */

const TASK_SUCCEED = 0x1ec01b;
const TASK_FAIL = 0x1ec01c;
const TASK_AND_THEN = 0x1ec01d;
const TASK_MAP = 0x1ec01e;
const TASK_SPAWN = 0x1ec01f;
const TASK_SLEEP = 0x1ec020;
const TASK_ON_ERROR = 0x1ec021;
const TASK_HTTP_GET_JSON = 0x1ec022;
const TASK_HTTP_GET_WITH_OPTIONS = 0x1ec023;
const TASK_HTTP_REQUEST = 0x1ec024;

const BACKEND_TASK_EXPECT_JSON = 1;
const BACKEND_TASK_EXPECT_STRING = 2;
const BACKEND_TASK_EXPECT_WHATEVER = 3;
const BACKEND_TASK_EXPECT_BYTES = 4;
const BACKEND_TASK_EXPECT_METADATA = 5;

const BACKEND_TASK_BODY_EMPTY = 1;
const BACKEND_TASK_BODY_STRING = 2;
const BACKEND_TASK_BODY_JSON = 3;
const BACKEND_TASK_BODY_BYTES = 4;

export function createTaskRuntime(deps) {
  const {
    RC_SUCCESS,
    RC_ERR_UNIMPLEMENTED,
    allocHandle,
    readHandle,
    writeOut,
    intValue,
    stringValue,
    invokeClosure,
    tuple2,
    makeTuple2Handle = null,
    retainHandle = null,
    releaseHandle = null,
    addOwner = null,
    tupleFirst,
    tupleSecond,
    newIntHandle,
    newStringHandle,
    newList,
    cmdNoneHandle,
    TAG_TUPLE2,
    TAG_INT,
    TAG_RESULT,
    TAG_CMD,
    TAG_RECORD,
    TAG_LIST,
    TAG_MAYBE,
    TAG_BYTES,
    dispatchPlatformMsg,
    jsonDecodeRunString = null,
    bytesDecodeRun = null,
    readOutSlot = null,
    jsonBodyTextFromValue = null,
    newBytesFromView = null,
    bytesView = null,
    fetchFn = typeof fetch !== "undefined" ? fetch.bind(globalThis) : null,
    constructorTags = {},
    unitHandle = 0,
    jsonDecodeErrorToString = null,
  } = deps;

  let browserCacheWarned = false;

  const constructorTag = (qualifiedName) => {
    if (constructorTags[qualifiedName] != null) {
      return constructorTags[qualifiedName] | 0;
    }

    const short = qualifiedName.split(".").pop();
    if (constructorTags[short] != null) {
      return constructorTags[short] | 0;
    }

    return null;
  };

  const makeUnionWithTag = (tag, payloadPtr) =>
    allocHandle({
      tag: TAG_TUPLE2,
      first: newIntHandle(tag | 0),
      second: payloadPtr | 0,
    });

  const makeHttpTaskFailure = (name, payloadPtr, fallbackMessage) => {
    const tag = constructorTag(`BackendTask.Http.${name}`);
    if (tag != null) {
      return taskToResult(false, makeUnionWithTag(tag, payloadPtr | 0));
    }

    return taskToResult(false, newStringHandle(fallbackMessage));
  };

  /** @type {Set<number>} */
  const pendingTimers = new Set();

  const isTaskHandle = (ptr) => {
    const payload = readHandle(ptr);
    return payload?.tag === TAG_RESULT && payload.taskKind != null;
  };

  const taskWrap = (kind, valuePtr) => {
    const value = valuePtr | 0;
    const handle = allocHandle({
      tag: TAG_RESULT,
      isOk: true,
      taskKind: kind,
      value,
    });
    // Transfer ownership of `value` into the task (no extra retain). Callers that
    // keep a parallel owned-slot ref must retain before wrapping.
    if (value && addOwner) addOwner(value, handle);
    return handle;
  };

  // `tuple2(out, …)` writes through an out-pointer and returns RC — not a handle.
  const makeTuple2 = (firstPtr, secondPtr) => {
    if (typeof makeTuple2Handle === "function") {
      return makeTuple2Handle(firstPtr | 0, secondPtr | 0);
    }
    // Fallback without ownership (tests that don't pass makeTuple2Handle).
    return allocHandle({
      tag: TAG_TUPLE2,
      first: firstPtr | 0,
      second: secondPtr | 0,
    });
  };

  const taskWrapPair = (kind, firstPtr, secondPtr) =>
    taskWrap(kind, makeTuple2(firstPtr | 0, secondPtr | 0));

  const taskToResult = (ok, valuePtr) =>
    allocHandle({
      tag: TAG_RESULT,
      isOk: ok,
      value: valuePtr | 0,
    });

  const isAsyncForce = (forced) =>
    Boolean(
      forced &&
        (forced.httpGetJson ||
          forced.httpGetWithOptions ||
          forced.httpRequest ||
          (forced.async && forced.rc === RC_ERR_UNIMPLEMENTED))
    );

  const withCont = (forced, step) => ({
    ...forced,
    cont: [...(forced.cont || []), step],
  });

  const forceTask = (taskPtr) => {
    const payload = readHandle(taskPtr);
    if (!payload || payload.taskKind == null) {
      return { rc: RC_SUCCESS, value: taskPtr | 0 };
    }

    switch (payload.taskKind) {
      case TASK_SUCCEED:
        return { rc: RC_SUCCESS, value: taskToResult(true, payload.value | 0) };
      case TASK_FAIL:
        return { rc: RC_SUCCESS, value: taskToResult(false, payload.value | 0) };
      case TASK_SLEEP:
        return { rc: RC_ERR_UNIMPLEMENTED, value: 0, async: true, ms: intValue(payload.value | 0) };
      case TASK_ON_ERROR: {
        const pair = readHandle(payload.value);
        if (pair?.tag !== TAG_TUPLE2) return { rc: RC_ERR_UNIMPLEMENTED, value: 0 };
        const forced = forceTask(pair.second | 0);
        if (isAsyncForce(forced)) {
          return withCont(forced, { kind: "onError", fn: pair.first | 0 });
        }
        if (forced.rc !== RC_SUCCESS) return forced;
        const resultPayload = readHandle(forced.value);
        if (resultPayload?.isOk) return { rc: RC_SUCCESS, value: forced.value };
        const recovered = invokeClosure(pair.first | 0, [resultPayload.value | 0]);
        if (recovered.rc !== RC_SUCCESS) return recovered;
        return forceTask(recovered.value | 0);
      }
      case TASK_MAP: {
        const pair = readHandle(payload.value);
        if (pair?.tag !== TAG_TUPLE2) return { rc: RC_ERR_UNIMPLEMENTED, value: 0 };
        const forced = forceTask(pair.second | 0);
        if (isAsyncForce(forced)) {
          return withCont(forced, { kind: "map", fn: pair.first | 0 });
        }
        if (forced.rc !== RC_SUCCESS) return forced;
        const resultPayload = readHandle(forced.value);
        if (!resultPayload?.isOk) return { rc: RC_SUCCESS, value: forced.value };
        const mapped = invokeClosure(pair.first | 0, [resultPayload.value | 0]);
        if (mapped.rc !== RC_SUCCESS) return mapped;
        return { rc: RC_SUCCESS, value: taskToResult(true, mapped.value | 0) };
      }
      case TASK_AND_THEN: {
        const pair = readHandle(payload.value);
        if (pair?.tag !== TAG_TUPLE2) return { rc: RC_ERR_UNIMPLEMENTED, value: 0 };
        const forced = forceTask(pair.second | 0);
        if (isAsyncForce(forced)) {
          return withCont(forced, { kind: "andThen", fn: pair.first | 0 });
        }
        if (forced.rc !== RC_SUCCESS) return forced;
        const resultPayload = readHandle(forced.value);
        if (!resultPayload?.isOk) return { rc: RC_SUCCESS, value: forced.value };
        const next = invokeClosure(pair.first | 0, [resultPayload.value | 0]);
        if (next.rc !== RC_SUCCESS) return next;
        return forceTask(next.value | 0);
      }
      case TASK_HTTP_GET_JSON:
        return {
          rc: RC_ERR_UNIMPLEMENTED,
          value: 0,
          async: true,
          httpGetJson: { taskPtr: taskPtr | 0 },
        };
      case TASK_HTTP_GET_WITH_OPTIONS:
        return {
          rc: RC_ERR_UNIMPLEMENTED,
          value: 0,
          async: true,
          httpGetWithOptions: { taskPtr: taskPtr | 0 },
        };
      case TASK_HTTP_REQUEST:
        return {
          rc: RC_ERR_UNIMPLEMENTED,
          value: 0,
          async: true,
          httpRequest: { taskPtr: taskPtr | 0 },
        };
      default:
        return { rc: RC_ERR_UNIMPLEMENTED, value: 0 };
    }
  };

  const urlFromRecordFields = (fields) => {
    for (const ptr of fields ?? []) {
      const value = stringValue(ptr | 0);
      if (value.startsWith("http://") || value.startsWith("https://") || value.startsWith("/")) {
        return value;
      }
    }
    return "";
  };

  const resolveExpect = (expectPtr) => {
    const expect = readHandle(expectPtr);
    if (!expect) return null;

    if (expect.backendTaskExpectKind === BACKEND_TASK_EXPECT_STRING) {
      return { kind: "string" };
    }

    if (expect.backendTaskExpectKind === BACKEND_TASK_EXPECT_JSON) {
      return { kind: "json", decoderPtr: expect.fields?.[0] ?? 0 };
    }

    if (expect.backendTaskExpectKind === BACKEND_TASK_EXPECT_WHATEVER) {
      return { kind: "whatever", valuePtr: expect.fields?.[0] ?? 0 };
    }

    if (expect.backendTaskExpectKind === BACKEND_TASK_EXPECT_BYTES) {
      return { kind: "bytes", decoderPtr: expect.fields?.[0] ?? 0 };
    }

    if (expect.tag === TAG_RECORD && expect.fields?.[0]) {
      return { kind: "json", decoderPtr: expect.fields[0] };
    }

    return null;
  };

  const headersFromListPtr = (listPtr) => {
    const list = readHandle(listPtr);
    if (list?.tag !== TAG_LIST) return [];

    const headers = [];
    for (const pairPtr of list.items ?? []) {
      const pair = readHandle(pairPtr);
      if (pair?.tag === TAG_TUPLE2) {
        headers.push([stringValue(pair.first | 0), stringValue(pair.second | 0)]);
      }
    }
    return headers;
  };

  const readMaybeInt = (maybePtr) => {
    const maybe = readHandle(maybePtr);
    if (maybe?.tag !== TAG_MAYBE || maybe.value == null) return 0;
    const payload = readHandle(maybe.value);
    return payload?.tag === TAG_INT ? payload.value | 0 : 0;
  };

  const maybeIsJust = (maybePtr) => {
    const maybe = readHandle(maybePtr);
    return maybe?.tag === TAG_MAYBE && maybe.value != null;
  };

  // Elm stores record fields alphabetically. `buildGetOptionsRecord` uses source
  // declaration order (url-first). Detect which layout we have.
  const parseGetOptionsFields = (fields) => {
    const list = fields ?? [];
    const first = stringValue(list[0] | 0);
    const declarationOrder =
      first.startsWith("http://") || first.startsWith("https://") || first.startsWith("/");

    if (declarationOrder) {
      return {
        url: first,
        expectPtr: list[1] ?? 0,
        headerPairs: headersFromListPtr(list[2] ?? 0),
        retries: readMaybeInt(list[4] ?? 0),
        timeoutMs: readMaybeInt(list[5] ?? 0),
        cacheStrategyJust: maybeIsJust(list[3] ?? 0),
        cachePathJust: maybeIsJust(list[6] ?? 0),
      };
    }

    // Alphabetical: cachePath, cacheStrategy, expect, headers, retries, timeoutInMs, url
    return {
      url: urlFromRecordFields(list),
      expectPtr: list[2] ?? 0,
      headerPairs: headersFromListPtr(list[3] ?? 0),
      retries: readMaybeInt(list[4] ?? 0),
      timeoutMs: readMaybeInt(list[5] ?? 0),
      cacheStrategyJust: maybeIsJust(list[1] ?? 0),
      cachePathJust: maybeIsJust(list[0] ?? 0),
    };
  };

  const headersFromOptionsFields = (fields) => parseGetOptionsFields(fields).headerPairs;

  const warnIfBrowserCacheIgnored = (fields) => {
    if (browserCacheWarned) return;
    const parsed = parseGetOptionsFields(fields);
    if (parsed.cacheStrategyJust || parsed.cachePathJust) {
      browserCacheWarned = true;
      console.warn(
        "[elmc-wasm-runtime] BackendTask.Http cacheStrategy/cachePath are ignored in browser WASM builds; requests use fetch directly."
      );
    }
  };

  const timeoutFromOptionsFields = (fields) => parseGetOptionsFields(fields).timeoutMs;

  const parseRequestRecord = (fields) => ({
    url: stringValue(fields[0] | 0),
    method: stringValue(fields[1] | 0) || "GET",
    headerPairs: headersFromListPtr(fields[2] ?? 0),
    bodyPtr: fields[3] ?? 0,
    retries: readMaybeInt(fields[4] ?? 0),
    timeoutMs: readMaybeInt(fields[5] ?? 0),
  });

  const prepareBodyForFetch = (bodyPtr, headerPairs) => {
    const body = readHandle(bodyPtr);
    const headers = [...headerPairs];
    if (!body) return { bodyInit: undefined, headerPairs: headers };

    if (body.backendTaskBodyKind === BACKEND_TASK_BODY_EMPTY) {
      return { bodyInit: undefined, headerPairs: headers };
    }

    if (body.backendTaskBodyKind === BACKEND_TASK_BODY_STRING) {
      const contentType = stringValue(body.fields?.[0] | 0);
      const content = stringValue(body.fields?.[1] | 0);
      if (contentType && !headers.some(([key]) => key.toLowerCase() === "content-type")) {
        headers.push(["Content-Type", contentType]);
      }
      return { bodyInit: content, headerPairs: headers };
    }

    if (body.backendTaskBodyKind === BACKEND_TASK_BODY_JSON) {
      const content = body.encodedJson ?? "";
      if (!headers.some(([key]) => key.toLowerCase() === "content-type")) {
        headers.push(["Content-Type", "application/json"]);
      }
      return { bodyInit: content, headerPairs: headers };
    }

    if (body.backendTaskBodyKind === BACKEND_TASK_BODY_BYTES) {
      const contentType = stringValue(body.fields?.[0] | 0);
      const bytesPtr = body.fields?.[1] ?? 0;
      const view = typeof bytesView === "function" ? bytesView(bytesPtr) : null;
      if (view) {
        const arr = new Uint8Array(view.buffer, view.byteOffset, view.byteLength);
        if (contentType && !headers.some(([key]) => key.toLowerCase() === "content-type")) {
          headers.push(["Content-Type", contentType]);
        }
        return { bodyInit: arr, headerPairs: headers };
      }
    }

    return { bodyInit: undefined, headerPairs: headers };
  };

  const maybeNothingHandle = () => allocHandle({ tag: TAG_MAYBE, value: null });

  const maybeJustHandle = (valuePtr) =>
    allocHandle({ tag: TAG_MAYBE, value: valuePtr | 0, isJust: true, ctorTag: 1 });

  const makeJsonDecodeFailureFromMessage = (message) => {
    const tag = constructorTag("Json.Decode.Failure");
    if (tag == null) return null;
    return makeUnionWithTag(tag, newStringHandle(message));
  };

  const makeBadBodyFailure = (message, decodeErrorPtr = null) => {
    const structuredPtr = decodeErrorPtr ?? makeJsonDecodeFailureFromMessage(message);
    const maybePtr = structuredPtr ? maybeJustHandle(structuredPtr) : maybeNothingHandle();
    const bodyText =
      structuredPtr && typeof jsonDecodeErrorToString === "function"
        ? jsonDecodeErrorToString(structuredPtr)
        : message;
    return makeHttpTaskFailure(
      "BadBody",
      makeTuple2(maybePtr, newStringHandle(bodyText)),
      bodyText
    );
  };

  const unwrapMetadataChain = (expectPtr) => {
    const combines = [];
    let current = expectPtr | 0;

    while (current) {
      const expect = readHandle(current);
      if (expect?.backendTaskExpectKind !== BACKEND_TASK_EXPECT_METADATA) {
        return { combines, innerExpectPtr: current };
      }

      combines.push(expect.fields?.[0] ?? 0);
      current = expect.fields?.[1] ?? 0;
    }

    return { combines, innerExpectPtr: 0 };
  };

  const ownHandle = (ptr) => {
    const handle = ptr | 0;
    if (handle && retainHandle) retainHandle(handle);
    return handle;
  };

  // Record fields: retain only handles the caller still owns separately. Fresh
  // allocs (rc=1) are transferred into the record without an extra retain.
  const allocOwnedRecord = (fields, extra = {}) => {
    const ownedFields = fields ?? [];
    const handle = allocHandle({
      tag: TAG_RECORD,
      fields: ownedFields,
      ...extra,
    });
    if (addOwner) {
      for (const field of ownedFields) {
        if (field) addOwner(field | 0, handle);
      }
    }
    return handle;
  };

  const buildGetOptionsRecord = (urlPtr, expectPtr, headersPtr = null) => {
    const headers = headersPtr != null ? ownHandle(headersPtr) : newList([]);
    return allocOwnedRecord([
      ownHandle(urlPtr),
      ownHandle(expectPtr),
      headers,
      maybeNothingHandle(),
      maybeNothingHandle(),
      maybeNothingHandle(),
      maybeNothingHandle(),
    ]);
  };

  const decodeJsonResponse = async (decoderPtr, text) => {
    if (!jsonDecodeRunString || !readOutSlot) {
      return makeHttpTaskFailure("NetworkError", unitHandle, "BackendTask.Http unavailable");
    }

    const scratchOut = 12288;
    const decodeRc = jsonDecodeRunString(scratchOut, decoderPtr, newStringHandle(text));
    if (decodeRc !== RC_SUCCESS) {
      return makeBadBodyFailure("JSON decode failed");
    }

    const resultHandle = readOutSlot(scratchOut);
    if (!resultHandle) {
      return makeBadBodyFailure("JSON decode failed");
    }

    if (resultHandle.isOk) {
      return taskToResult(true, resultHandle.value | 0);
    }

    const errText =
      resultHandle.value != null
        ? typeof jsonDecodeErrorToString === "function"
          ? jsonDecodeErrorToString(resultHandle.value | 0)
          : stringValue(resultHandle.value | 0)
        : "JSON decode failed";
    return makeBadBodyFailure(errText, resultHandle.value | 0);
  };

  const decodeBytesResponse = async (decoderPtr, arrayBuffer) => {
    if (!bytesDecodeRun || !newBytesFromView || !readOutSlot) {
      return makeHttpTaskFailure("NetworkError", unitHandle, "BackendTask.Http unavailable");
    }

    const bytesPtr = newBytesFromView(new DataView(arrayBuffer));
    const scratchOut = 12288;
    const decodeRc = bytesDecodeRun(scratchOut, decoderPtr, bytesPtr);
    if (decodeRc !== RC_SUCCESS) {
      return makeBadBodyFailure("Bytes decoding failed.");
    }

    const maybeHandle = readOutSlot(scratchOut);
    if (!maybeHandle || maybeHandle.tag !== TAG_MAYBE || maybeHandle.value == null) {
      return makeBadBodyFailure("Bytes decoding failed.");
    }

    return taskToResult(true, maybeHandle.value | 0);
  };

  const makeMetadataHandle = (url, response, headerPairs) => {
    const headerItems = [];
    if (response.headers?.forEach) {
      response.headers.forEach((value, key) => {
        headerItems.push(makeTuple2(newStringHandle(key), newStringHandle(value)));
      });
    } else {
      for (const [key, value] of headerPairs) {
        headerItems.push(makeTuple2(newStringHandle(key), newStringHandle(value)));
      }
    }

    // Declaration-order Metadata (matches BackendTask.Http.Metadata / Http.Metadata
    // alias shapes): url, statusCode, statusText, headers. Alphabetical would still
    // put statusCode at index 1, but url/headers disagree with plan field indices.
    return allocHandle({
      tag: TAG_RECORD,
      fields: [
        newStringHandle(response.url || url),
        newIntHandle(response.status | 0),
        newStringHandle(response.statusText || ""),
        newList(headerItems),
      ],
    });
  };

  const invokeCombine = (combineFnPtr, metadataPtr, valuePtr) => {
    const combined = invokeClosure(combineFnPtr, [metadataPtr | 0, valuePtr | 0]);
    if (combined.rc !== RC_SUCCESS || !combined.value) return 0;
    return combined.value | 0;
  };

  const processResponse = async (expectPtr, response, url, headerPairs = []) => {
    const { combines, innerExpectPtr } = unwrapMetadataChain(expectPtr);
    const resolved = resolveExpect(innerExpectPtr);
    if (!resolved) {
      return taskToResult(false, newStringHandle("BackendTask.Http expect unsupported"));
    }

    const metadataPtr =
      combines.length > 0 ? makeMetadataHandle(url, response, headerPairs) : 0;

    const finishWithCombines = (valuePtr) => {
      if (combines.length === 0) {
        return taskToResult(true, valuePtr);
      }

      let current = valuePtr;
      for (let i = combines.length - 1; i >= 0; i--) {
        current = invokeCombine(combines[i], metadataPtr, current);
        if (!current) {
          return taskToResult(false, newStringHandle("BackendTask.Http withMetadata failed"));
        }
      }

      return taskToResult(true, current);
    };

    if (resolved.kind === "whatever") {
      return finishWithCombines(resolved.valuePtr);
    }

    if (resolved.kind === "bytes") {
      const buffer = await response.arrayBuffer();
      const decoded = await decodeBytesResponse(resolved.decoderPtr, buffer);
      const payload = readHandle(decoded);
      if (!payload?.isOk) return decoded;
      return finishWithCombines(payload.value | 0);
    }

    const text = await response.text();
    if (resolved.kind === "string") {
      return finishWithCombines(newStringHandle(text));
    }

    const decoded = await decodeJsonResponse(resolved.decoderPtr, text);
    const decodedPayload = readHandle(decoded);
    if (!decodedPayload?.isOk) return decoded;
    return finishWithCombines(decodedPayload.value | 0);
  };

  const fetchBackendTaskHttp = async ({
    url,
    expectPtr,
    method = "GET",
    bodyInit,
    timeoutMs = 0,
    headerPairs = [],
    retries = 0,
  }) => {
    if (!fetchFn) {
      return {
        rc: RC_SUCCESS,
        value: makeHttpTaskFailure("NetworkError", unitHandle, "BackendTask.Http unavailable"),
      };
    }

    const headers = new Headers();
    for (const [key, value] of headerPairs) {
      headers.append(key, value);
    }

    let lastFailure = makeHttpTaskFailure("NetworkError", unitHandle, "Network error");

    for (let attempt = 0; attempt <= retries; attempt++) {
      const controller = typeof AbortController !== "undefined" ? new AbortController() : null;
      let timeoutId = null;
      if (controller && timeoutMs > 0) {
        timeoutId = setTimeout(() => controller.abort(), timeoutMs);
      }

      try {
        const response = await fetchFn(url, {
          method,
          headers,
          body: bodyInit,
          signal: controller?.signal,
        });
        if (timeoutId) clearTimeout(timeoutId);

        if (!response.ok) {
          const errText = await response.text();
          const metadataPtr = makeMetadataHandle(url, response, headerPairs);
          lastFailure = makeHttpTaskFailure(
            "BadStatus",
            makeTuple2(metadataPtr, newStringHandle(errText)),
            `Bad status ${response.status}: ${errText}`
          );
          if (attempt < retries) continue;
          return { rc: RC_SUCCESS, value: lastFailure };
        }

        return {
          rc: RC_SUCCESS,
          value: await processResponse(expectPtr, response, url, headerPairs),
        };
      } catch (err) {
        if (timeoutId) clearTimeout(timeoutId);
        const message = err?.message ? String(err.message) : "Network error";
        const isTimeout = err?.name === "AbortError";
        lastFailure = isTimeout
          ? makeHttpTaskFailure("Timeout", unitHandle, message)
          : makeHttpTaskFailure("NetworkError", unitHandle, message);
        if (attempt < retries) continue;
        return { rc: RC_SUCCESS, value: lastFailure };
      }
    }

    return { rc: RC_SUCCESS, value: lastFailure };
  };

  const fetchJsonTask = async (url, decoderPtr, timeoutMs = 0, headerPairs = []) => {
    const expectPtr = allocHandle({
      tag: TAG_RECORD,
      fields: [decoderPtr | 0],
      backendTaskExpectKind: BACKEND_TASK_EXPECT_JSON,
    });
    return fetchBackendTaskHttp({
      url,
      expectPtr,
      timeoutMs,
      headerPairs,
    });
  };

  const runHttpGetJsonTask = async (taskPtr) => {
    const payload = readHandle(taskPtr);
    const pair = payload?.value != null ? readHandle(payload.value | 0) : null;
    if (pair?.tag !== TAG_TUPLE2) {
      return { rc: RC_SUCCESS, value: taskToResult(false, newStringHandle("BackendTask.Http")) };
    }

    const url = stringValue(pair.first | 0);
    const decoderPtr = pair.second | 0;
    return fetchJsonTask(url, decoderPtr);
  };

  const runHttpGetWithOptionsTask = async (taskPtr) => {
    const payload = readHandle(taskPtr);
    const optionsPtr = payload?.value | 0;
    const options = readHandle(optionsPtr);
    if (!options || options.tag !== TAG_RECORD) {
      return { rc: RC_SUCCESS, value: taskToResult(false, newStringHandle("BackendTask.Http")) };
    }

    const fields = options.fields ?? [];
    warnIfBrowserCacheIgnored(fields);
    const parsed = parseGetOptionsFields(fields);

    if (!parsed.url || !parsed.expectPtr) {
      return {
        rc: RC_SUCCESS,
        value: taskToResult(false, newStringHandle("BackendTask.Http.getWithOptions")),
      };
    }

    return fetchBackendTaskHttp({
      url: parsed.url,
      expectPtr: parsed.expectPtr,
      timeoutMs: parsed.timeoutMs,
      headerPairs: parsed.headerPairs,
      retries: parsed.retries,
    });
  };

  const runHttpRequestTask = async (taskPtr) => {
    const payload = readHandle(taskPtr);
    const pair = payload?.value != null ? readHandle(payload.value | 0) : null;
    if (pair?.tag !== TAG_TUPLE2) {
      return { rc: RC_SUCCESS, value: taskToResult(false, newStringHandle("BackendTask.Http")) };
    }

    const req = readHandle(pair.first | 0);
    const expectPtr = pair.second | 0;
    if (!req || req.tag !== TAG_RECORD) {
      return { rc: RC_SUCCESS, value: taskToResult(false, newStringHandle("BackendTask.Http.request")) };
    }

    const parsed = parseRequestRecord(req.fields ?? []);
    const { bodyInit, headerPairs } = prepareBodyForFetch(parsed.bodyPtr, parsed.headerPairs);

    if (!parsed.url || !expectPtr) {
      return {
        rc: RC_SUCCESS,
        value: taskToResult(false, newStringHandle("BackendTask.Http.request")),
      };
    }

    return fetchBackendTaskHttp({
      url: parsed.url,
      expectPtr,
      method: parsed.method,
      bodyInit,
      timeoutMs: parsed.timeoutMs,
      headerPairs,
      retries: parsed.retries,
    });
  };

  const applyTaskCont = async (result, cont) => {
    let current = result;
    for (const step of cont || []) {
      if (!current || current.rc !== RC_SUCCESS || !current.value) return current;
      const resultPayload = readHandle(current.value);
      if (!resultPayload) return current;

      if (step.kind === "andThen") {
        // Propagate Err so a later onError can recover.
        if (!resultPayload.isOk) continue;
        const next = invokeClosure(step.fn | 0, [resultPayload.value | 0]);
        if (next.rc !== RC_SUCCESS) return next;
        current = await runTaskAsync(next.value | 0);
        continue;
      }

      if (step.kind === "onError") {
        if (resultPayload.isOk) continue;
        const recovered = invokeClosure(step.fn | 0, [resultPayload.value | 0]);
        if (recovered.rc !== RC_SUCCESS) return recovered;
        current = await runTaskAsync(recovered.value | 0);
        continue;
      }

      if (step.kind === "map") {
        if (!resultPayload.isOk) continue;
        const mapped = invokeClosure(step.fn | 0, [resultPayload.value | 0]);
        if (mapped.rc !== RC_SUCCESS) return mapped;
        current = { rc: RC_SUCCESS, value: taskToResult(true, mapped.value | 0) };
      }
    }
    return current;
  };

  const runTaskAsync = (taskPtr) =>
    new Promise((resolve) => {
      const run = () => {
        const forced = forceTask(taskPtr);
        const {
          rc,
          value,
          async: isAsync,
          ms,
          httpGetJson,
          httpGetWithOptions,
          httpRequest,
          cont,
        } = forced;

        const finish = (result) => applyTaskCont(result, cont).then(resolve);

        if (httpGetJson) {
          runHttpGetJsonTask(httpGetJson.taskPtr).then(finish);
          return;
        }
        if (httpGetWithOptions) {
          runHttpGetWithOptionsTask(httpGetWithOptions.taskPtr).then(finish);
          return;
        }
        if (httpRequest) {
          runHttpRequestTask(httpRequest.taskPtr).then(finish);
          return;
        }
        if (isAsync && rc === RC_ERR_UNIMPLEMENTED) {
          const timer = setTimeout(() => {
            pendingTimers.delete(timer);
            finish({ rc: RC_SUCCESS, value: taskToResult(true, newIntHandle(0)) });
          }, Math.max(0, ms | 0));
          pendingTimers.add(timer);
          return;
        }
        finish({ rc, value });
      };
      queueMicrotask(run);
    });

  const taskSucceed = (outPtr, valuePtr) => {
    writeOut(outPtr, taskWrap(TASK_SUCCEED, valuePtr | 0));
    return RC_SUCCESS;
  };

  const taskFail = (outPtr, valuePtr) => {
    // Sync probes `case Task.fail n of Ok/Err` match TAG_RESULT.isOk.
    // Box raw i32 payloads so Err arms bind a real Int handle (not handle id n).
    const value =
      valuePtr && readHandle(valuePtr | 0)
        ? valuePtr | 0
        : newIntHandle(valuePtr | 0);
    if (retainHandle) retainHandle(value);
    writeOut(
      outPtr,
      allocHandle({ tag: TAG_RESULT, isOk: false, taskKind: TASK_FAIL, value })
    );
    return RC_SUCCESS;
  };

  const taskMap = (outPtr, fnPtr, taskPtr) => {
    writeOut(outPtr, taskWrapPair(TASK_MAP, fnPtr | 0, taskPtr | 0));
    return RC_SUCCESS;
  };

  const taskMap2 = (outPtr, fnPtr, aPtr, bPtr) => {
    const pair = makeTuple2(aPtr | 0, bPtr | 0);
    writeOut(outPtr, taskWrapPair(TASK_MAP, fnPtr | 0, pair));
    return RC_SUCCESS;
  };

  const taskAndThen = (outPtr, fnPtr, taskPtr) => {
    writeOut(outPtr, taskWrapPair(TASK_AND_THEN, fnPtr | 0, taskPtr | 0));
    return RC_SUCCESS;
  };

  const taskOnError = (outPtr, fnPtr, taskPtr) => {
    writeOut(outPtr, taskWrapPair(TASK_ON_ERROR, fnPtr | 0, taskPtr | 0));
    return RC_SUCCESS;
  };

  const backendTaskHttpGetJson = (outPtr, urlPtr, decoderPtr) => {
    writeOut(outPtr, taskWrapPair(TASK_HTTP_GET_JSON, urlPtr | 0, decoderPtr | 0));
    return RC_SUCCESS;
  };

  const backendTaskHttpGet = (outPtr, urlPtr, expectPtr) => {
    const optionsPtr = buildGetOptionsRecord(urlPtr, expectPtr);
    writeOut(outPtr, taskWrap(TASK_HTTP_GET_WITH_OPTIONS, optionsPtr));
    return RC_SUCCESS;
  };

  const backendTaskHttpExpectJson = (outPtr, decoderPtr) => {
    writeOut(
      outPtr,
      allocOwnedRecord([ownHandle(decoderPtr)], {
        backendTaskExpectKind: BACKEND_TASK_EXPECT_JSON,
      })
    );
    return RC_SUCCESS;
  };

  const backendTaskHttpExpectString = (outPtr) => {
    writeOut(
      outPtr,
      allocHandle({
        tag: TAG_RECORD,
        fields: [],
        backendTaskExpectKind: BACKEND_TASK_EXPECT_STRING,
      })
    );
    return RC_SUCCESS;
  };

  const backendTaskHttpExpectWhatever = (outPtr, valuePtr) => {
    writeOut(
      outPtr,
      allocOwnedRecord([ownHandle(valuePtr)], {
        backendTaskExpectKind: BACKEND_TASK_EXPECT_WHATEVER,
      })
    );
    return RC_SUCCESS;
  };

  const backendTaskHttpExpectBytes = (outPtr, decoderPtr) => {
    writeOut(
      outPtr,
      allocOwnedRecord([ownHandle(decoderPtr)], {
        backendTaskExpectKind: BACKEND_TASK_EXPECT_BYTES,
      })
    );
    return RC_SUCCESS;
  };

  const backendTaskHttpWithMetadata = (outPtr, combineFnPtr, originalExpectPtr) => {
    writeOut(
      outPtr,
      allocOwnedRecord([ownHandle(combineFnPtr), ownHandle(originalExpectPtr)], {
        backendTaskExpectKind: BACKEND_TASK_EXPECT_METADATA,
      })
    );
    return RC_SUCCESS;
  };

  const backendTaskHttpEmptyBody = (outPtr) => {
    writeOut(
      outPtr,
      allocHandle({
        tag: TAG_RECORD,
        fields: [],
        backendTaskBodyKind: BACKEND_TASK_BODY_EMPTY,
      })
    );
    return RC_SUCCESS;
  };

  const backendTaskHttpStringBody = (outPtr, contentTypePtr, contentPtr) => {
    writeOut(
      outPtr,
      allocOwnedRecord([ownHandle(contentTypePtr), ownHandle(contentPtr)], {
        backendTaskBodyKind: BACKEND_TASK_BODY_STRING,
      })
    );
    return RC_SUCCESS;
  };

  const backendTaskHttpJsonBody = (outPtr, valuePtr) => {
    const encodedJson =
      typeof jsonBodyTextFromValue === "function"
        ? jsonBodyTextFromValue(valuePtr | 0)
        : null;
    writeOut(
      outPtr,
      allocOwnedRecord([ownHandle(valuePtr)], {
        backendTaskBodyKind: BACKEND_TASK_BODY_JSON,
        encodedJson: encodedJson ?? "null",
      })
    );
    return RC_SUCCESS;
  };

  const backendTaskHttpBytesBody = (outPtr, contentTypePtr, bytesPtr) => {
    writeOut(
      outPtr,
      allocOwnedRecord([ownHandle(contentTypePtr), ownHandle(bytesPtr)], {
        backendTaskBodyKind: BACKEND_TASK_BODY_BYTES,
      })
    );
    return RC_SUCCESS;
  };

  const buildPostRequestRecord = (urlPtr, bodyPtr) =>
    allocOwnedRecord([
      ownHandle(urlPtr),
      newStringHandle("POST"),
      newList([]),
      ownHandle(bodyPtr),
      maybeNothingHandle(),
      maybeNothingHandle(),
    ]);

  const backendTaskHttpRequest = (outPtr, reqPtr, expectPtr) => {
    writeOut(outPtr, taskWrapPair(TASK_HTTP_REQUEST, reqPtr | 0, expectPtr | 0));
    return RC_SUCCESS;
  };

  const backendTaskHttpPost = (outPtr, urlPtr, bodyPtr, expectPtr) => {
    const reqPtr = buildPostRequestRecord(urlPtr, bodyPtr);
    writeOut(outPtr, taskWrapPair(TASK_HTTP_REQUEST, reqPtr, expectPtr | 0));
    return RC_SUCCESS;
  };

  const backendTaskHttpGetWithOptions = (outPtr, optionsPtr) => {
    writeOut(outPtr, taskWrap(TASK_HTTP_GET_WITH_OPTIONS, optionsPtr | 0));
    return RC_SUCCESS;
  };

  // Task.perform / Task.attempt lower to `(Perform task)` as tuple2(1, task).
  // WASM imports are `(out, cmdDesc)` — not `(out, toMsg, task)`.
  const unwrapPerformTask = (cmdDescPtr) => {
    const desc = readHandle(cmdDescPtr | 0);
    if (desc?.tag === TAG_TUPLE2) {
      return desc.second | 0;
    }
    return cmdDescPtr | 0;
  };

  const dispatchTaskMsg = (taskPtr) => {
    const ptr = taskPtr | 0;
    // Survive Task.attempt / init owned-slot epilogues that release the Perform
    // wrapper and the task between scheduling and the microtask.
    if (ptr && retainHandle) retainHandle(ptr);
    runTaskAsync(ptr)
      .then(({ rc, value }) => {
        try {
          if (rc !== RC_SUCCESS || !value) return;
          const result = readHandle(value);
          // Task.attempt/perform map failures into Ok(msg); only Ok payloads are msgs.
          if (!result?.isOk) return;
          if (dispatchPlatformMsg && result.value) {
            dispatchPlatformMsg(result.value);
          }
        } finally {
          if (value && releaseHandle) releaseHandle(value);
          if (ptr && releaseHandle) releaseHandle(ptr);
        }
      })
      .catch(() => {
        if (ptr && releaseHandle) releaseHandle(ptr);
      });
  };

  const taskPerform = (outPtr, cmdDescPtr) => {
    dispatchTaskMsg(unwrapPerformTask(cmdDescPtr));
    writeOut(outPtr, cmdNoneHandle());
    return RC_SUCCESS;
  };

  // Effect-module `command (Perform task)` — same descriptor shape as task_perform.
  const taskCommand = (outPtr, cmdDescPtr) => {
    dispatchTaskMsg(unwrapPerformTask(cmdDescPtr));
    writeOut(outPtr, cmdNoneHandle());
    return RC_SUCCESS;
  };

  const timeNowMillis = (outPtr) => {
    const now = Date.now();
    writeOut(outPtr, taskWrap(TASK_SUCCEED, newIntHandle(now)));
    return RC_SUCCESS;
  };

  const processSpawn = (outPtr, taskPtr) => {
    runTaskAsync(taskPtr | 0);
    writeOut(outPtr, taskToResult(true, newIntHandle(1)));
    return RC_SUCCESS;
  };

  const processSleep = (outPtr, _msPtr) => {
    writeOut(outPtr, taskToResult(true, unitHandle | 0));
    return RC_SUCCESS;
  };

  const processKill = (outPtr, _pidPtr) => {
    for (const timer of pendingTimers) clearTimeout(timer);
    pendingTimers.clear();
    writeOut(outPtr, taskToResult(true, unitHandle | 0));
    return RC_SUCCESS;
  };

  return {
    taskSucceed,
    taskFail,
    taskMap,
    taskMap2,
    taskAndThen,
    taskOnError,
    taskPerform,
    taskCommand,
    backendTaskHttpGetJson,
    backendTaskHttpGet,
    backendTaskHttpExpectJson,
    backendTaskHttpExpectString,
    backendTaskHttpExpectWhatever,
    backendTaskHttpExpectBytes,
    backendTaskHttpWithMetadata,
    backendTaskHttpEmptyBody,
    backendTaskHttpStringBody,
    backendTaskHttpJsonBody,
    backendTaskHttpBytesBody,
    backendTaskHttpRequest,
    backendTaskHttpPost,
    backendTaskHttpGetWithOptions,
    timeNowMillis,
    processSpawn,
    processSleep,
    processKill,
    drainTaskCmd: async (cmdPtr) => {
      const payload = readHandle(cmdPtr);
      if (!payload) return;
      if (payload.tag === TAG_CMD && payload.kind === "task") {
        await runTaskAsync(payload.task | 0);
      }
    },
  };
}
