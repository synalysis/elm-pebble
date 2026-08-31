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
const TASK_FILE_READ = 0x1ec025;
const TASK_MAP2 = 0x1ec026;
const TASK_SEQUENCE = 0x1ec027;
export const TASK_HTTP_ELM = 0x1ec028;

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
    listItems = null,
    cmdNoneHandle,
    TAG_TUPLE2,
    TAG_INT,
    TAG_FLOAT = 4,
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
    runElmHttpTask = null,
  } = deps;

  let readNativeFile = deps.readNativeFile || null;
  const setReadNativeFile = (fn) => {
    readNativeFile = typeof fn === "function" ? fn : null;
  };

  let runElmHttpTaskImpl = typeof runElmHttpTask === "function" ? runElmHttpTask : null;
  const setRunElmHttpTask = (fn) => {
    runElmHttpTaskImpl = typeof fn === "function" ? fn : null;
  };

  let browserCacheWarned = false;

  // Official `Process.sleep : Float -> Task x ()`. Prefer a boxed float;
  // `intValue` on TAG_FLOAT returns the handle id, not milliseconds.
  const sleepMs = (ptr) => {
    const p = ptr | 0;
    if (!p) return 0;
    const payload = readHandle(p);
    if (payload?.tag === TAG_FLOAT) {
      const ms = Number(payload.value);
      return Number.isFinite(ms) ? Math.max(0, ms) : 0;
    }
    if (payload?.tag === TAG_INT) {
      return Math.max(0, payload.value | 0);
    }
    return Math.max(0, p);
  };

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

  /** @type {Set<ReturnType<typeof setTimeout>>} */
  const pendingTimers = new Set();
  /** @type {Map<number, { timers: Set<ReturnType<typeof setTimeout>>, aborts: Set<AbortController>, killed: boolean }>} */
  const processes = new Map();
  let nextPid = 1;

  const MAIN_PID = 0;

  const ensureProcess = (pid) => {
    const id = pid | 0;
    if (id === MAIN_PID) return null;
    let proc = processes.get(id);
    if (!proc) {
      proc = { timers: new Set(), aborts: new Set(), killed: false };
      processes.set(id, proc);
    }
    return proc;
  };

  const isKilled = (pid) => {
    const id = pid | 0;
    if (id === MAIN_PID) return false;
    return processes.get(id)?.killed === true;
  };

  const registerTimer = (pid, timer) => {
    pendingTimers.add(timer);
    const proc = ensureProcess(pid);
    if (proc) proc.timers.add(timer);
  };

  const unregisterTimer = (pid, timer) => {
    pendingTimers.delete(timer);
    processes.get(pid | 0)?.timers.delete(timer);
  };

  const registerAbort = (pid, controller) => {
    const proc = ensureProcess(pid);
    if (proc && controller) proc.aborts.add(controller);
  };

  const unregisterAbort = (pid, controller) => {
    processes.get(pid | 0)?.aborts.delete(controller);
  };

  const processAbortController = (pid) => {
    if (typeof AbortController === "undefined") return null;
    const controller = new AbortController();
    registerAbort(pid, controller);
    return controller;
  };

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
          forced.httpElmTask ||
          forced.fileRead ||
          (forced.async && forced.rc === RC_ERR_UNIMPLEMENTED))
    );

  const withCont = (forced, step) => ({
    ...forced,
    cont: [...(forced.cont || []), step],
  });

  const forceSequence = (items, acc) => {
    const remaining = Array.isArray(items) ? items : [];
    if (!remaining.length) {
      return { rc: RC_SUCCESS, value: taskToResult(true, newList(acc)) };
    }
    const head = remaining[0] | 0;
    const rest = remaining.slice(1);
    const forced = forceTask(head);
    if (isAsyncForce(forced)) {
      return withCont(forced, { kind: "sequence", rest, acc });
    }
    if (forced.rc !== RC_SUCCESS) return forced;
    const resultPayload = readHandle(forced.value);
    if (!resultPayload?.isOk) return { rc: RC_SUCCESS, value: forced.value };
    return forceSequence(rest, [...acc, resultPayload.value | 0]);
  };

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
        return { rc: RC_ERR_UNIMPLEMENTED, value: 0, async: true, ms: sleepMs(payload.value | 0) };
      case TASK_FILE_READ:
        return {
          rc: RC_ERR_UNIMPLEMENTED,
          value: 0,
          async: true,
          fileRead: {
            filePtr: payload.value | 0,
            kind: payload.fileReadKind || "string",
          },
        };
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
      case TASK_MAP2: {
        const pair = readHandle(payload.value);
        if (pair?.tag !== TAG_TUPLE2) return { rc: RC_ERR_UNIMPLEMENTED, value: 0 };
        const tasks = readHandle(pair.second | 0);
        if (tasks?.tag !== TAG_TUPLE2) return { rc: RC_ERR_UNIMPLEMENTED, value: 0 };
        const fn = pair.first | 0;
        const fa = forceTask(tasks.first | 0);
        if (isAsyncForce(fa)) {
          return withCont(fa, { kind: "map2_b", fn, b: tasks.second | 0 });
        }
        if (fa.rc !== RC_SUCCESS) return fa;
        const ra = readHandle(fa.value);
        if (!ra?.isOk) return { rc: RC_SUCCESS, value: fa.value };
        const fb = forceTask(tasks.second | 0);
        if (isAsyncForce(fb)) {
          return withCont(fb, { kind: "map2_apply", fn, aVal: ra.value | 0 });
        }
        if (fb.rc !== RC_SUCCESS) return fb;
        const rb = readHandle(fb.value);
        if (!rb?.isOk) return { rc: RC_SUCCESS, value: fb.value };
        const mapped = invokeClosure(fn, [ra.value | 0, rb.value | 0]);
        if (mapped.rc !== RC_SUCCESS) return mapped;
        return { rc: RC_SUCCESS, value: taskToResult(true, mapped.value | 0) };
      }
      case TASK_SEQUENCE: {
        const items = listItems ? listItems(payload.value | 0) : [];
        return forceSequence(items, []);
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
      case TASK_HTTP_ELM:
        return {
          rc: RC_ERR_UNIMPLEMENTED,
          value: 0,
          async: true,
          httpElmTask: { taskPtr: taskPtr | 0 },
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

  const asMaybeInt = (ptr) => {
    const payload = readHandle(ptr | 0);
    if (!payload) return 0;
    if (payload.tag === TAG_INT) return payload.value | 0;
    if (payload.tag === TAG_FLOAT) {
      const n = Number(payload.value);
      return Number.isFinite(n) ? n | 0 : 0;
    }
    return 0;
  };

  // Official Elm Maybe is tuple2(ctor, payload) / INT 0 (Nothing). Host TAG_MAYBE
  // is the JS-native wrapper used by some runtime constructors.
  const readMaybeInt = (maybePtr) => {
    const maybe = readHandle(maybePtr);
    if (!maybe) return 0;
    if (maybe.tag === TAG_MAYBE) {
      if (maybe.value == null || maybe.isJust === false) return 0;
      return asMaybeInt(maybe.value);
    }
    if (maybe.tag === TAG_TUPLE2) {
      const ctor = intValue(maybe.first | 0);
      if (ctor === 0) return 0;
      return asMaybeInt(maybe.second | 0);
    }
    if (maybe.tag === TAG_INT) return maybe.value | 0;
    return 0;
  };

  const maybeIsJust = (maybePtr) => {
    const maybe = readHandle(maybePtr);
    if (!maybe) return false;
    if (maybe.tag === TAG_MAYBE) return maybe.value != null && maybe.isJust !== false;
    if (maybe.tag === TAG_TUPLE2) return intValue(maybe.first | 0) !== 0;
    if (maybe.tag === TAG_INT) return (maybe.value | 0) !== 0;
    return false;
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
    pid = MAIN_PID,
    processController = null,
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
      if (isKilled(pid) || processController?.signal?.aborted) {
        return { rc: RC_SUCCESS, value: 0, killed: true };
      }
      // Dedicated fetch controller: timeoutInMs must not abort processController,
      // or the catch path treats Timeout as a killed Process and never dispatches.
      const controller =
        typeof AbortController !== "undefined" ? new AbortController() : processController;
      const unlinkKill =
        controller && processController?.signal && controller !== processController
          ? (() => {
              const onKill = () => controller.abort();
              processController.signal.addEventListener("abort", onKill);
              return () => processController.signal.removeEventListener("abort", onKill);
            })()
          : () => {};
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
        unlinkKill();

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
        unlinkKill();
        if (isKilled(pid) || processController?.signal?.aborted) {
          return { rc: RC_SUCCESS, value: 0, killed: true };
        }
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

  const fetchJsonTask = async (url, decoderPtr, timeoutMs = 0, headerPairs = [], extra = {}) => {
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
      ...extra,
    });
  };

  const runHttpGetJsonTask = async (taskPtr, extra = {}) => {
    const payload = readHandle(taskPtr);
    const pair = payload?.value != null ? readHandle(payload.value | 0) : null;
    if (pair?.tag !== TAG_TUPLE2) {
      return { rc: RC_SUCCESS, value: taskToResult(false, newStringHandle("BackendTask.Http")) };
    }

    const url = stringValue(pair.first | 0);
    const decoderPtr = pair.second | 0;
    return fetchJsonTask(url, decoderPtr, 0, [], extra);
  };

  const runHttpGetWithOptionsTask = async (taskPtr, extra = {}) => {
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
      ...extra,
    });
  };

  const runHttpRequestTask = async (taskPtr, extra = {}) => {
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
      ...extra,
    });
  };

  const applyTaskCont = async (result, cont, pid = MAIN_PID) => {
    if (result?.killed || isKilled(pid)) {
      return result?.killed ? result : { rc: RC_SUCCESS, value: 0, killed: true };
    }
    let current = result;
    for (const step of cont || []) {
      if (isKilled(pid)) return { rc: RC_SUCCESS, value: 0, killed: true };
      if (!current || current.rc !== RC_SUCCESS || !current.value) return current;
      const resultPayload = readHandle(current.value);
      if (!resultPayload) return current;

      if (step.kind === "andThen") {
        // Propagate Err so a later onError can recover.
        if (!resultPayload.isOk) continue;
        const next = invokeClosure(step.fn | 0, [resultPayload.value | 0]);
        if (next.rc !== RC_SUCCESS) return next;
        current = await runTaskAsync(next.value | 0, pid);
        continue;
      }

      if (step.kind === "onError") {
        if (resultPayload.isOk) continue;
        const recovered = invokeClosure(step.fn | 0, [resultPayload.value | 0]);
        if (recovered.rc !== RC_SUCCESS) return recovered;
        current = await runTaskAsync(recovered.value | 0, pid);
        continue;
      }

      if (step.kind === "map") {
        if (!resultPayload.isOk) continue;
        const mapped = invokeClosure(step.fn | 0, [resultPayload.value | 0]);
        if (mapped.rc !== RC_SUCCESS) return mapped;
        current = { rc: RC_SUCCESS, value: taskToResult(true, mapped.value | 0) };
        continue;
      }

      if (step.kind === "map2_b") {
        if (!resultPayload.isOk) continue;
        const aVal = resultPayload.value | 0;
        current = await runTaskAsync(step.b | 0, pid);
        if (!current || current.rc !== RC_SUCCESS || !current.value) return current;
        const bPayload = readHandle(current.value);
        if (!bPayload?.isOk) continue;
        const mapped = invokeClosure(step.fn | 0, [aVal, bPayload.value | 0]);
        if (mapped.rc !== RC_SUCCESS) return mapped;
        current = { rc: RC_SUCCESS, value: taskToResult(true, mapped.value | 0) };
        continue;
      }

      if (step.kind === "map2_apply") {
        if (!resultPayload.isOk) continue;
        const mapped = invokeClosure(step.fn | 0, [step.aVal | 0, resultPayload.value | 0]);
        if (mapped.rc !== RC_SUCCESS) return mapped;
        current = { rc: RC_SUCCESS, value: taskToResult(true, mapped.value | 0) };
        continue;
      }

      if (step.kind === "sequence") {
        if (!resultPayload.isOk) continue;
        const acc = [...(step.acc || []), resultPayload.value | 0];
        let rest = step.rest || [];
        for (const taskPtr of rest) {
          current = await runTaskAsync(taskPtr | 0, pid);
          if (!current || current.rc !== RC_SUCCESS || !current.value) return current;
          const item = readHandle(current.value);
          if (!item?.isOk) return current;
          acc.push(item.value | 0);
        }
        current = { rc: RC_SUCCESS, value: taskToResult(true, newList(acc)) };
      }
    }
    return current;
  };

  const runTaskAsync = (taskPtr, pid = MAIN_PID) =>
    new Promise((resolve) => {
      const run = () => {
        if (isKilled(pid)) {
          resolve({ rc: RC_SUCCESS, value: 0, killed: true });
          return;
        }
        const forced = forceTask(taskPtr);
        const {
          rc,
          value,
          async: isAsync,
          ms,
          httpGetJson,
          httpGetWithOptions,
          httpRequest,
          httpElmTask,
          fileRead,
          cont,
        } = forced;

        const finish = (result) => {
          if (isKilled(pid)) {
            resolve({ rc: RC_SUCCESS, value: 0, killed: true });
            return;
          }
          applyTaskCont(result, cont, pid).then(resolve);
        };

        if (httpGetJson) {
          const controller = processAbortController(pid);
          runHttpGetJsonTask(httpGetJson.taskPtr, { pid, processController: controller }).then(
            (result) => {
              unregisterAbort(pid, controller);
              finish(result);
            }
          );
          return;
        }
        if (httpGetWithOptions) {
          const controller = processAbortController(pid);
          runHttpGetWithOptionsTask(httpGetWithOptions.taskPtr, {
            pid,
            processController: controller,
          }).then((result) => {
            unregisterAbort(pid, controller);
            finish(result);
          });
          return;
        }
        if (httpRequest) {
          const controller = processAbortController(pid);
          runHttpRequestTask(httpRequest.taskPtr, { pid, processController: controller }).then(
            (result) => {
              unregisterAbort(pid, controller);
              finish(result);
            }
          );
          return;
        }
        if (httpElmTask) {
          const runner = runElmHttpTaskImpl;
          if (!runner) {
            finish({
              rc: RC_SUCCESS,
              value: taskToResult(false, newStringHandle("Http.task unavailable")),
            });
            return;
          }
          const controller = processAbortController(pid);
          runner(httpElmTask.taskPtr, controller).then((result) => {
            unregisterAbort(pid, controller);
            finish(result);
          });
          return;
        }
        if (fileRead) {
          const reader = readNativeFile;
          if (!reader) {
            finish({
              rc: RC_SUCCESS,
              value: taskToResult(false, newStringHandle("File")),
            });
            return;
          }
          reader(fileRead.kind, fileRead.filePtr).then((result) => {
            if (!result?.ok) {
              finish({
                rc: RC_SUCCESS,
                value: taskToResult(false, newStringHandle(result?.error || "File")),
              });
              return;
            }
            if (fileRead.kind === "bytes") {
              const view = result.value
                ? new DataView(result.value)
                : new DataView(new ArrayBuffer(0));
              const bytesPtr = newBytesFromView
                ? newBytesFromView(view)
                : newIntHandle(0);
              finish({ rc: RC_SUCCESS, value: taskToResult(true, bytesPtr) });
              return;
            }
            finish({
              rc: RC_SUCCESS,
              value: taskToResult(true, newStringHandle(String(result.value ?? ""))),
            });
          });
          return;
        }
        if (isAsync && rc === RC_ERR_UNIMPLEMENTED) {
          const timer = setTimeout(() => {
            unregisterTimer(pid, timer);
            if (isKilled(pid)) {
              finish({ rc: RC_SUCCESS, value: 0, killed: true });
              return;
            }
            finish({ rc: RC_SUCCESS, value: taskToResult(true, unitHandle | 0) });
          }, Math.max(0, ms | 0));
          registerTimer(pid, timer);
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
    writeOut(outPtr, taskWrapPair(TASK_MAP2, fnPtr | 0, pair));
    return RC_SUCCESS;
  };

  const taskSequence = (outPtr, listPtr) => {
    writeOut(outPtr, taskWrap(TASK_SEQUENCE, listPtr | 0));
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

  const dispatchTaskMsg = (taskPtr, taggers = []) => {
    const ptr = taskPtr | 0;
    // Survive Task.attempt / init owned-slot epilogues that release the Perform
    // wrapper and the task between scheduling and the microtask.
    if (ptr && retainHandle) retainHandle(ptr);
    return runTaskAsync(ptr)
      .then(({ rc, value }) => {
        try {
          if (rc !== RC_SUCCESS || !value) return;
          const result = readHandle(value);
          // Task.attempt/perform map failures into Ok(msg); only Ok payloads are msgs.
          if (!result?.isOk) return;
          let msg = result.value | 0;
          for (const taggerPtr of taggers ?? []) {
            if (!taggerPtr) continue;
            const next = invokeClosure(taggerPtr | 0, [msg]);
            if (next.rc !== RC_SUCCESS) return;
            msg = next.value | 0;
          }
          if (dispatchPlatformMsg && msg) {
            dispatchPlatformMsg(msg);
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

  // Official Task.perform returns a Cmd the platform drains (so Cmd.map taggers
  // compose after toMsg). Do not dispatch during the perform call.
  const writeTaskCmd = (outPtr, cmdDescPtr) => {
    const taskPtr = unwrapPerformTask(cmdDescPtr);
    if (taskPtr && retainHandle) retainHandle(taskPtr);
    writeOut(
      outPtr,
      allocHandle({
        tag: TAG_CMD,
        kind: "task",
        task: taskPtr | 0,
      })
    );
    return RC_SUCCESS;
  };

  const taskPerform = writeTaskCmd;

  // Effect-module `command (Perform task)` — same descriptor shape as task_perform.
  const taskCommand = writeTaskCmd;

  const timeNowMillis = (outPtr) => {
    const now = Date.now();
    writeOut(outPtr, taskWrap(TASK_SUCCEED, newIntHandle(now)));
    return RC_SUCCESS;
  };

  const wrapFileRead = (outPtr, kind, filePtr) => {
    const ptr = filePtr | 0;
    const handle = allocHandle({
      tag: TAG_RESULT,
      isOk: true,
      taskKind: TASK_FILE_READ,
      value: ptr,
      fileReadKind: kind,
    });
    // Same retain as file_select toMsg: the caller releases the File after
    // File.toString / toBytes / toUrl return, before runTaskAsync reads it.
    if (ptr && retainHandle) retainHandle(ptr);
    if (ptr && addOwner) addOwner(ptr, handle);
    writeOut(outPtr, handle);
    return RC_SUCCESS;
  };

  const taskFileToString = (outPtr, filePtr) => wrapFileRead(outPtr, "string", filePtr);
  const taskFileToBytes = (outPtr, filePtr) => wrapFileRead(outPtr, "bytes", filePtr);
  const taskFileToUrl = (outPtr, filePtr) => wrapFileRead(outPtr, "url", filePtr);

  const processSpawn = (outPtr, taskPtr) => {
    const pid = nextPid++;
    ensureProcess(pid);
    const ptr = taskPtr | 0;
    // Same retain as Task.perform: the caller releases the task slot after
    // spawn returns, before the queued runTaskAsync microtask.
    if (ptr && retainHandle) retainHandle(ptr);
    runTaskAsync(ptr, pid).finally(() => {
      if (ptr && releaseHandle) releaseHandle(ptr);
    });
    writeOut(outPtr, taskToResult(true, newIntHandle(pid)));
    return RC_SUCCESS;
  };

  const processSleep = (outPtr, msPtr) => {
    writeOut(outPtr, taskWrap(TASK_SLEEP, msPtr | 0));
    return RC_SUCCESS;
  };

  const processKill = (outPtr, pidPtr) => {
    const pid = intValue(pidPtr);
    const proc = processes.get(pid);
    if (proc) {
      proc.killed = true;
      for (const timer of proc.timers) {
        clearTimeout(timer);
        pendingTimers.delete(timer);
      }
      proc.timers.clear();
      for (const controller of proc.aborts) {
        try {
          controller.abort();
        } catch (_err) {
          /* ignore */
        }
      }
      proc.aborts.clear();
    }
    writeOut(outPtr, taskToResult(true, unitHandle | 0));
    return RC_SUCCESS;
  };

  return {
    taskSucceed,
    taskFail,
    taskMap,
    taskMap2,
    taskSequence,
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
    taskFileToString,
    taskFileToBytes,
    taskFileToUrl,
    setReadNativeFile,
    setRunElmHttpTask,
    processSpawn,
    processSleep,
    processKill,
    drainTaskCmd: async (cmdPtr, taggers = []) => {
      const payload = readHandle(cmdPtr);
      if (!payload) return;
      if (payload.tag === TAG_CMD && payload.kind === "task") {
        await dispatchTaskMsg(payload.task | 0, taggers);
      }
    },
  };
}
