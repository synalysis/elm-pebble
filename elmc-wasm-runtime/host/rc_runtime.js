/**
 * Elm RC runtime for elmc WASM modules (Phase 1 execution harness).
 *
 * Imports follow the wasm ABI: (out_ptr, ...args) -> RC i32, writing result
 * handles into linear memory at out_ptr.
 */

import { createJsonRuntime } from "./json_runtime.js";
import { createBytesRuntime } from "./bytes_runtime.js";
import { createParserRuntime } from "./parser_runtime.js";
import { createHttpRuntime } from "./http_runtime.js";
import { createTaskRuntime } from "./task_runtime.js";
import { createFileRuntime } from "./file_runtime.js";
import { createRandomRuntime } from "./random_runtime.js";
import { createRegexRuntime } from "./regex_runtime.js";
import { createUrlRuntime } from "./url_runtime.js";
import { createRouteBytesRuntime } from "./route_bytes.js";
import { createNavigationRuntime } from "./navigation_runtime.js";
import { createVdomPatchRuntime } from "./vdom_patch.js";
import { createDomEventRuntime } from "./dom_event_runtime.js";

export const RC_SUCCESS = 0;
export const RC_ERR_UNIMPLEMENTED = 100;

const TAG_INT = 1;
const TAG_LIST = 2;
const TAG_MAYBE = 3;
const TAG_FLOAT = 4;
const TAG_CLOSURE = 5;
const TAG_TUPLE2 = 6;
const TAG_STRING = 7;
const TAG_RESULT = 8;
const TAG_CHAR = 9;
const TAG_ORDER = 10;
const TAG_RECORD = 11;
const TAG_VDOM = 12;
const TAG_BROWSER_PROGRAM = 13;
const TAG_CMD = 14;
const TAG_SUB = 15;
const TAG_BYTES = 16;
const TAG_FORWARD_REF = 17;

const HTML_KIND_TEXT = 1;
const HTML_KIND_NODE = 2;
const HTML_KIND_MAP = 3;
const HTML_KIND_ATTR = 4;
const HTML_KIND_STYLE = 5;
const HTML_KIND_LAZY = 6;
const HTML_KIND_NODE_NS = 7;
const HTML_KIND_EVENT = 8;
const HTML_KIND_PROPERTY = 14;
const HTML_KIND_KEYED = 9;
const HTML_KIND_KEYED_NS = 10;
const HTML_KIND_LAZY2 = 11;
const HTML_KIND_LAZY3 = 12;
const HTML_KIND_LAZY4 = 13;
const HTML_KIND_CMD_NONE = 0;

const BROWSER_KIND_APPLICATION = 1;
const BROWSER_KIND_LOAD = 2;
const BROWSER_KIND_PUSH_URL = 3;
const BROWSER_KIND_REPLACE_URL = 4;
const BROWSER_KIND_SET_VIEWPORT = 5;
const BROWSER_KIND_ELEMENT = 6;
const BROWSER_KIND_DOCUMENT = 7;
const BROWSER_KIND_WORKER = 8;
const BROWSER_KIND_FOCUS = 9;
const BROWSER_KIND_BACK = 10;
const BROWSER_KIND_FORWARD = 11;
const BROWSER_KIND_SET_TITLE = 12;
const BROWSER_KIND_GET_VIEWPORT = 13;

const DOM_SUB_NONE = 0;
const DOM_SUB_TIME_EVERY = 1;
const DOM_SUB_ON_RESIZE = 2;
const DOM_SUB_ON_VISIBILITY = 3;
const DOM_SUB_ON_ANIMATION_FRAME = 4;
const DOM_SUB_ON_MOUSE_MOVE = 5;
const DOM_SUB_ON_CLICK = 6;
const DOM_SUB_ON_KEY_DOWN = 7;
const DOM_SUB_ON_KEY_UP = 8;
const DOM_SUB_HTTP_TRACK = 9;

export function createRcRuntime({ immortalStrings = {}, constructorTags = {} } = {}) {
  let memory = null;
  let nextHandle = 2;
  const handles = new Map();
  const orderHandles = new Map();
  let retainCount = 0;
  let invokeClosureExport = null;
  let literalStrings = Array.isArray(immortalStrings) ? immortalStrings : { ...immortalStrings };
  /** Interned immortal string handles keyed by dense literal id. */
  const immortalStringHandles = new Map();
  /** @type {number[][]} */
  const callRootStack = [];
  /** @type {(msgPtr: number) => void} */
  let dispatchPlatformMsgRef = () => {};
  /** @type {Map<string, number>} */
  const incomingPortHandlers = new Map();
  /** @type {Map<number, { dispose: () => void }>} */
  const activeDomSubs = new Map();
  /** @type {Map<string, number>} */
  const lazyHtmlCache = new Map();
  let nextDomSubId = 1;
  /** @type {{ port: string, payload: number }[]} */
  const outgoingPortQueue = [];

  const lookupImmortalString = (literalId) => {
    if (Array.isArray(literalStrings)) {
      return literalStrings[literalId | 0] ?? "";
    }
    return literalStrings[String(literalId)] ?? "";
  };

  const UNIT_HANDLE = 1;
  handles.set(UNIT_HANDLE, { tag: TAG_INT, value: 0, immortal: true });

  const setClosureInvoker = (fn) => {
    invokeClosureExport = fn;
  };

  const setImmortalStrings = (table) => {
    literalStrings = Array.isArray(table) ? table : { ...table };
    immortalStringHandles.clear();
  };

  const setMemory = (mem) => {
    memory = mem;
  };

  const view = () => new DataView(memory.buffer);

  const allocHandle = (payload) => {
    const handle = nextHandle++;
    const rc = payload.immortal ? 1_000_000 : payload.rc ?? 1;
    handles.set(handle, { ...payload, rc });
    return handle;
  };

  let cloneHandleForProgram = (handlePtr) => handlePtr | 0;
  /** Clone port payloads so init/subscriptions cannot invalidate caller-owned handles. */
  let cloneIncomingPortPayload = (payloadPtr) => payloadPtr | 0;

  const writeOut = (outPtr, handle) => {
    if (outPtr) view().setUint32(outPtr, handle, true);
  };

  const readHandle = (ptr) => (ptr ? handles.get(ptr) : null);

  const intValue = (ptr) => {
    if (!ptr) return 0;
    const payload = handles.get(ptr);
    return payload?.tag === TAG_INT ? payload.value | 0 : ptr | 0;
  };

  const asIntNumber = (ptr) => {
    if (!ptr) return 0;
    const payload = readHandle(ptr);
    if (!payload) return ptr | 0;
    if (payload.tag === TAG_FLOAT) return payload.value | 0;
    if (payload.tag === TAG_INT) return payload.value | 0;
    return intValue(ptr);
  };

  const asBoolForWasm = (ptr) => {
    const p = ptr | 0;
    const payload = readHandle(p);
    // Bool temps may pass raw i32 0/1 that collide with early immortal Int handles.
    if (payload?.tag === TAG_INT && payload.immortal && p <= 255) {
      return p;
    }
    return intValue(p);
  };

  const unionTagAsInt = (handlePtr) => {
    if (!handlePtr) return -1;
    const payload = readHandle(handlePtr);
    if (!payload) return handlePtr | 0;

    switch (payload.tag) {
      case TAG_INT:
        return payload.value | 0;
      case TAG_TUPLE2: {
        let tagPtr = payload.first | 0;
        let tagPayload = readHandle(tagPtr);
        // Custom-type messages may encode the variant as (tag, unit) in the first
        // field and carry the real payload in the second field.
        while (tagPayload?.tag === TAG_TUPLE2) {
          const innerFirst = readHandle(tagPayload.first);
          if (innerFirst?.tag === TAG_INT) {
            return innerFirst.value | 0;
          }
          tagPtr = tagPayload.first | 0;
          tagPayload = readHandle(tagPtr);
        }
        return intValue(tagPtr);
      }
      case TAG_RESULT: {
        if (payload.ctorTag != null) return payload.ctorTag | 0;
        return payload.isOk ? 1 : 0;
      }
      case TAG_MAYBE: {
        if (payload.ctorTag != null) return payload.ctorTag | 0;
        return payload.value != null ? 1 : 0;
      }
      default:
        return -1;
    }
  };

  // Sub/port taggers emit full Platform.Msg values (FrozenViewsReady tag 11,
  // HotReloadCompleteNew tag 9, Platform.UrlChanged tag 2, etc.). onUrlRequest
  // and DOM decoders emit app-level Msg values that must be wrapped as
  // Platform.UserMsg (tag 3) before Platform.update.
  const PLATFORM_OUTER_MSG_TAGS = new Set([2, 3, 9, 10, 11, 12]);

  const isElmPagesPlatformProgram = () => incomingPortHandlers.has("pageDataFromJs");

  const wrapIncomingPlatformMsg = (msgPtr) => {
    if (!msgPtr || !isElmPagesPlatformProgram()) return msgPtr;
    const tag = unionTagAsInt(msgPtr);
    if (PLATFORM_OUTER_MSG_TAGS.has(tag)) return msgPtr;
    return allocHandle({
      tag: TAG_TUPLE2,
      first: newIntHandle(3),
      second: msgPtr | 0,
    });
  };

  const unionTagMatches = (outPtr, handlePtr, tagPtr) => {
    // WASM/C codegen pass constructor tags as raw i32 immediates (elmc_int_t),
    // not boxed handles — never resolve tagPtr through the handle table.
    const want = tagPtr | 0;
    return newInt(outPtr, unionTagAsInt(handlePtr) === want ? 1 : 0);
  };

  const newIntHandle = (value) => allocHandle({ tag: TAG_INT, value: value | 0 });

  const unit = (outPtr) => {
    writeOut(outPtr, UNIT_HANDLE);
    return RC_SUCCESS;
  };

  let browserProgram = null;
  /** @type {{ implPtr: number, modelPtr: number, updateFn: number, viewFn: number, lastVdomPtr?: number, mountedRoot?: Node | null } | null} */
  let liveBrowser = null;
  let urlRuntimeApi = null;
  let routeBytesRuntime = null;
  let navigationRuntime = null;
  let vdomPatchRuntime = null;
  let domEventRuntime = null;
  /** @type {((portName: string, payload: Uint8Array | number) => Promise<unknown>) | null} */
  let deliverIncomingPortFn = null;
  const forwardRefs = new Map();

  const getForwardRefValue = (refKey) => {
    const stored = forwardRefs.get(refKey | 0);
    if (!stored) return newIntHandle(0);
    if (handles.has(stored)) {
      retain(null, stored);
      return stored;
    }
    return newIntHandle(wasmScalarArg(stored));
  };

  const newBrowserProgram = (implPtr) => {
    browserProgram = { impl: implPtr | 0 };
    return allocHandle({ tag: TAG_BROWSER_PROGRAM, impl: implPtr | 0 });
  };

  const recordField = (recordPtr, index) => {
    const fields = readHandle(recordPtr)?.fields ?? [];
    return fields[index] ?? 0;
  };

  const tupleFirst = (tuplePtr) => readHandle(tuplePtr)?.first ?? 0;
  const tupleSecond = (tuplePtr) => readHandle(tuplePtr)?.second ?? 0;

  const resolveHtml = (ptr, depth = 0) => {
    if (!ptr || depth > 8) return ptr;
    const payload = readHandle(ptr);
    if (!payload) return ptr;
    if (payload.tag === TAG_VDOM) {
      return ptr;
    }
    if (payload.tag === TAG_TUPLE2) {
      const kindPayload = readHandle(payload.first);
      if (kindPayload?.tag === TAG_INT) {
        const kind = kindPayload.value | 0;
        const childPtr = payload.second | 0;
        if (kind === HTML_KIND_MAP) {
          return ptr;
        }
      }
    }
    if (payload.tag === TAG_CLOSURE) {
      const { rc, value } = invokeClosure(ptr, []);
      if (rc !== RC_SUCCESS || !value) return ptr;
      const resolved = resolveHtml(value, depth + 1);
      if (value !== resolved && handles.has(value)) release(value);
      return resolved;
    }
    return ptr;
  };

  const forceLazyHtml = (fnPtr, argPtrs) => {
    let fnHandle = fnPtr | 0;
    let args = Array.isArray(argPtrs) ? argPtrs : argPtrs != null ? [argPtrs] : [];
    const lazyPayload = readHandle(fnHandle);
    if (lazyPayload?.tag === TAG_VDOM && lazyPayload.kind === "lazy") {
      fnHandle = lazyPayload.fn | 0;
      args = lazyPayload.args ?? [];
    }
    const cacheKey = `${fnHandle}|${args.map((a) => a | 0).join(",")}`;
    const cached = lazyHtmlCache.get(cacheKey);
    if (cached && handles.has(cached)) {
      retain(null, cached);
      return { rc: RC_SUCCESS, value: cached };
    }

    const payload = readHandle(fnHandle);
    if (payload?.tag !== TAG_CLOSURE) {
      return { rc: RC_SUCCESS, value: asHandle(fnHandle) };
    }

    const { rc, value } = invokeClosure(
      fnHandle,
      args.map((a) => asHandle(a | 0))
    );
    if (rc !== RC_SUCCESS) return { rc, value: 0 };
    const resolved = resolveHtml(value);
    if (!readHandle(resolved) || readHandle(resolved).tag !== TAG_VDOM) {
      return { rc: RC_ERR_UNIMPLEMENTED, value: 0 };
    }
    lazyHtmlCache.set(cacheKey, resolved);
    return { rc: RC_SUCCESS, value: resolved };
  };

  const viewTitleAndBodyFields = (payload) => {
    const fields = payload?.fields ?? [];
    if (fields.length < 2) return { titlePtr: fields[0] ?? 0, bodyPtr: fields[1] ?? 0 };

    let titlePtr = fields[0];
    let bodyPtr = fields[1];
    const first = readHandle(fields[0]);
    const second = readHandle(fields[1]);

    // Shared.template.view returns { body, title }; Browser.Document uses { title, body }.
    if (first?.tag === TAG_LIST && second?.tag === TAG_STRING) {
      titlePtr = fields[1];
      bodyPtr = fields[0];
    } else if (first?.tag === TAG_STRING && second?.tag === TAG_LIST) {
      titlePtr = fields[0];
      bodyPtr = fields[1];
    }

    return { titlePtr, bodyPtr };
  };

  const mountViewHandle = (viewPtr) => {
    const payload = readHandle(viewPtr);
    if (payload?.tag === TAG_RECORD && (payload.fields?.length ?? 0) >= 2) {
      const { titlePtr, bodyPtr } = viewTitleAndBodyFields(payload);
      if (typeof document !== "undefined") {
        const title = stringValue(titlePtr);
        if (title) document.title = title;
      }
      const root = ensureAppRoot();
      if (root && typeof document !== "undefined") {
        let wrapper = root.firstElementChild;
        if (!wrapper) {
          wrapper = document.createElement("div");
          root.replaceChildren(wrapper);
        }
        const bodyChild = listItems(bodyPtr)[0];
        if (bodyChild && vdomPatchRuntime && liveBrowser?.mountedRoot) {
          const patched = vdomPatchRuntime.patch(
            liveBrowser.lastVdomPtr ?? 0,
            asHandle(bodyChild),
            liveBrowser.mountedRoot
          );
          liveBrowser.mountedRoot = patched;
          liveBrowser.lastVdomPtr = asHandle(bodyChild);
        } else {
          const fragment = document.createDocumentFragment();
          for (const child of listItems(bodyPtr)) {
            const dom = vdomToDom(resolveHtml(asHandle(child)));
            if (dom) fragment.appendChild(dom);
          }
          wrapper.replaceChildren(fragment);
          if (liveBrowser) {
            liveBrowser.mountedRoot = wrapper.firstChild;
            liveBrowser.lastVdomPtr = asHandle(listItems(bodyPtr)[0] ?? 0);
          }
        }
      }
      return RC_SUCCESS;
    }

    if (vdomPatchRuntime && liveBrowser?.mountedRoot) {
      const patched = vdomPatchRuntime.patch(
        liveBrowser.lastVdomPtr ?? 0,
        viewPtr | 0,
        liveBrowser.mountedRoot
      );
      liveBrowser.mountedRoot = patched;
      liveBrowser.lastVdomPtr = viewPtr | 0;
      return RC_SUCCESS;
    }

    mountVdomToApp(viewPtr);
    if (liveBrowser && typeof document !== "undefined") {
      const root = ensureAppRoot();
      liveBrowser.mountedRoot = root?.firstElementChild?.firstChild ?? root?.firstChild ?? null;
      liveBrowser.lastVdomPtr = viewPtr | 0;
    }
    return RC_SUCCESS;
  };

  let createDefaultBootInputs = () => ({ flags: 0, url: 0, key: 0 });

  const browserViewFn = (implPtr) => {
    const impl = readHandle(implPtr);
    const fields = impl?.fields ?? [];
    const fieldCount = fields.length;

    // Browser.application: init, view, update, subscriptions, then onUrlRequest /
    // onUrlChange in record source order (elm-pages swaps these — navigation_runtime probes).
    if (fieldCount >= 6) {
      return fields[1] | 0;
    }

    // Browser.element / Browser.sandbox options record: init, view, update, subscriptions
    if (fieldCount === 4) {
      return fields[1] | 0;
    }

    for (let i = fieldCount - 1; i >= 0; i--) {
      const payload = readHandle(fields[i]);
      if (payload?.tag === TAG_CLOSURE && (payload.arity | 0) === 1) {
        return fields[i] | 0;
      }
    }

    return (fields[1] ?? fields[0] ?? 0) | 0;
  };

  const browserSubscriptionsFn = (implPtr) => {
    const impl = readHandle(implPtr);
    const fields = impl?.fields ?? [];
    if (fields.length >= 4) {
      return fields[3] | 0;
    }
    return 0;
  };

  const platformManagerTag = (tagNum) => newIntHandle(tagNum | 0);

  const platformManagerPort = (keyPtr, leafPtr) =>
    allocHandle({
      tag: TAG_RECORD,
      fields: [platformManagerTag(1), storeRecordField(keyPtr), storeRecordField(leafPtr)],
    });

  const platformManagerBatch = (itemsPtr) =>
    allocHandle({
      tag: TAG_RECORD,
      fields: [platformManagerTag(2), storeRecordField(itemsPtr)],
    });

  const platformManagerMap = (fnPtr, innerPtr) =>
    allocHandle({
      tag: TAG_RECORD,
      fields: [platformManagerTag(3), storeRecordField(fnPtr), storeRecordField(innerPtr)],
    });

  const listAllTag = (listPtr, tag) => {
    const items = listItems(listPtr);
    if (items.length === 0) return false;
    return items.every((item) => readHandle(item)?.tag === tag);
  };

  const cmdCellIsNone = (ptr) => {
    const payload = readHandle(ptr);
    return !ptr || (payload?.tag === TAG_INT && payload.value === 0);
  };

  const makeComposedIncomingHandler = (portCallbackPtr, taggers) => (payloadPtr) => {
    let { rc, value } = invokeClosure(portCallbackPtr, [asHandle(payloadPtr)]);
    if (rc !== RC_SUCCESS) return { rc, value: 0 };

    for (const taggerPtr of [...taggers].reverse()) {
      const next = invokeClosure(taggerPtr, [value]);
      if (
        value !== payloadPtr &&
        handles.has(value) &&
        !valueReaches(next.value, value)
      ) {
        release(value);
      }
      if (next.rc !== RC_SUCCESS) return next;
      value = next.value;
    }

    return { rc: RC_SUCCESS, value };
  };

  const clearDomSubs = () => {
    for (const sub of activeDomSubs.values()) sub.dispose();
    activeDomSubs.clear();
  };

  const dispatchTaggedMsg = (toMsgPtr, valuePtr, taggers) => {
    let value = valuePtr | 0;
    for (const taggerPtr of [...taggers].reverse()) {
      const next = invokeClosure(taggerPtr, [asHandle(value)]);
      if (value !== valuePtr && handles.has(value) && !valueReaches(next.value, value)) {
        release(value);
      }
      if (next.rc !== RC_SUCCESS) return next;
      value = next.value;
    }
    if (value) dispatchPlatformMsgRef(value);
    return { rc: RC_SUCCESS, value };
  };

  const installDomSub = (payload, taggers = []) => {
    const kind = payload.domKind | 0;
    const params = payload.params ?? [];
    const id = nextDomSubId++;
    let dispose = () => {};

    if (typeof window === "undefined") {
      activeDomSubs.set(id, { dispose });
      return;
    }

    if (kind === DOM_SUB_TIME_EVERY) {
      const interval = Math.max(1, intValue(params[0] | 0));
      const toMsgPtr = params[1] | 0;
      const tick = () => {
        dispatchTaggedMsg(toMsgPtr, newIntHandle(Date.now()), taggers);
      };
      const timer = setInterval(tick, interval);
      dispose = () => clearInterval(timer);
    } else if (kind === DOM_SUB_ON_RESIZE) {
      const toMsgPtr = params[0] | 0;
      const handler = () => {
        const pair = tuple2(0, newIntHandle(window.innerWidth), newIntHandle(window.innerHeight));
        dispatchTaggedMsg(toMsgPtr, pair, taggers);
      };
      window.addEventListener("resize", handler);
      handler();
      dispose = () => window.removeEventListener("resize", handler);
    } else if (kind === DOM_SUB_ON_VISIBILITY) {
      const toMsgPtr = params[0] | 0;
      const handler = () => {
        const visible = document.visibilityState === "visible" ? 1 : 0;
        dispatchTaggedMsg(toMsgPtr, newIntHandle(visible), taggers);
      };
      document.addEventListener("visibilitychange", handler);
      handler();
      dispose = () => document.removeEventListener("visibilitychange", handler);
    } else if (kind === DOM_SUB_ON_ANIMATION_FRAME) {
      const toMsgPtr = params[0] | 0;
      let frame = 0;
      const step = (time) => {
        frame = requestAnimationFrame(step);
        dispatchTaggedMsg(toMsgPtr, newIntHandle(time | 0), taggers);
      };
      frame = requestAnimationFrame(step);
      dispose = () => cancelAnimationFrame(frame);
    } else if (kind === DOM_SUB_ON_MOUSE_MOVE) {
      const toMsgPtr = params[0] | 0;
      const handler = (event) => {
        const payload = domEventRuntime?.mouseRecord(event) ?? newIntHandle(0);
        dispatchTaggedMsg(toMsgPtr, payload, taggers);
      };
      document.addEventListener("mousemove", handler);
      dispose = () => document.removeEventListener("mousemove", handler);
    } else if (kind === DOM_SUB_ON_CLICK) {
      const toMsgPtr = params[0] | 0;
      const handler = (event) => {
        const payload = domEventRuntime?.mouseRecord(event) ?? newIntHandle(0);
        dispatchTaggedMsg(toMsgPtr, payload, taggers);
      };
      document.addEventListener("click", handler);
      dispose = () => document.removeEventListener("click", handler);
    } else if (kind === DOM_SUB_ON_KEY_DOWN) {
      const toMsgPtr = params[0] | 0;
      const handler = (event) => {
        const payload = domEventRuntime?.keyboardRecord(event) ?? newIntHandle(0);
        dispatchTaggedMsg(toMsgPtr, payload, taggers);
      };
      document.addEventListener("keydown", handler);
      dispose = () => document.removeEventListener("keydown", handler);
    } else if (kind === DOM_SUB_ON_KEY_UP) {
      const toMsgPtr = params[0] | 0;
      const handler = (event) => {
        const payload = domEventRuntime?.keyboardRecord(event) ?? newIntHandle(0);
        dispatchTaggedMsg(toMsgPtr, payload, taggers);
      };
      document.addEventListener("keyup", handler);
      dispose = () => document.removeEventListener("keyup", handler);
    } else if (kind === DOM_SUB_HTTP_TRACK) {
      const tracker = stringValue(params[0] | 0);
      const toMsgPtr = params[1] | 0;
      http.registerProgressListener(tracker, toMsgPtr, taggers);
      dispose = () => http.unregisterProgressListener(tracker);
    }

    activeDomSubs.set(id, { dispose });
  };

  const resolveSubscriptionTree = (nodePtr, taggers = []) => {
    if (!nodePtr) return;

    const payload = readHandle(nodePtr);
    if (!payload) return;

    if (payload.tag === TAG_INT && payload.value === 0) return;

    if (payload.tag === TAG_LIST) {
      for (const item of listItems(nodePtr)) {
        resolveSubscriptionTree(item, taggers);
      }
      return;
    }

    if (payload.tag === TAG_SUB) {
      installDomSub(payload, taggers);
      return;
    }

    if (payload.tag !== TAG_RECORD) return;

    const tag = intValue(payload.fields[0]);
    if (tag === 1) {
      const portName = stringValue(payload.fields[1]);
      const leaf = payload.fields[2] | 0;
      if (portName && leaf) {
        incomingPortHandlers.set(portName, makeComposedIncomingHandler(leaf, taggers));
      }
      return;
    }

    if (tag === 2) {
      for (const item of listItems(payload.fields[1])) {
        resolveSubscriptionTree(item, taggers);
      }
      return;
    }

    if (tag === 3) {
      const fnPtr = payload.fields[1] | 0;
      resolveSubscriptionTree(payload.fields[2], [fnPtr, ...taggers]);
    }
  };

  const invokeIncomingHandler = (handler, payloadPtr) => {
    if (typeof handler === "function") {
      return handler(payloadPtr);
    }
    return invokeClosure(handler, [asHandle(payloadPtr)]);
  };

  const registerSubscriptions = (implPtr, initFn, modelPtr) => {
    const subFn = browserSubscriptionsFn(implPtr);
    if (!subFn) {
      return { rc: RC_SUCCESS };
    }

    incomingPortHandlers.clear();
    clearDomSubs();

    const result = invokeClosure(subFn, [modelPtr]);

    if (result.rc === RC_SUCCESS && result.value) {
      resolveSubscriptionTree(result.value);
    }

    return result;
  };

  const browserUpdateFn = (implPtr) => {
    const impl = readHandle(implPtr);
    const fields = impl?.fields ?? [];
    if (fields.length >= 3) {
      return fields[2] | 0;
    }
    return 0;
  };

  const isPlatformRecordModel = (payload) =>
    payload?.tag === TAG_RECORD && (payload.fields?.length ?? 0) >= 10;

  const readPlatformUpdateTuple = (updatePayload) => {
    if (updatePayload?.tag !== TAG_TUPLE2) {
      return { modelPtr: 0, sideEffectPtr: 0 };
    }
    const first = readHandle(updatePayload.first);
    const second = readHandle(updatePayload.second);
    const firstFields = first?.tag === TAG_RECORD ? first.fields?.length ?? 0 : -1;
    const secondFields = second?.tag === TAG_RECORD ? second.fields?.length ?? 0 : -1;
    if (firstFields >= 0 && secondFields >= 0) {
      if (firstFields >= secondFields) {
        return { modelPtr: updatePayload.first | 0, sideEffectPtr: updatePayload.second | 0 };
      }
      return { modelPtr: updatePayload.second | 0, sideEffectPtr: updatePayload.first | 0 };
    }
    if (firstFields >= 0) {
      return { modelPtr: updatePayload.first | 0, sideEffectPtr: updatePayload.second | 0 };
    }
    if (secondFields >= 0) {
      return { modelPtr: updatePayload.second | 0, sideEffectPtr: updatePayload.first | 0 };
    }
    return { modelPtr: updatePayload.first | 0, sideEffectPtr: updatePayload.second | 0 };
  };

  const drainPlatformSideEffect = async (effectPtr) => {
    const ptr = effectPtr | 0;
    if (!ptr) return;
    const payload = readHandle(ptr);
    if (!payload) return;

    if (payload.tag === TAG_INT) {
      const kind = payload.value | 0;
      if (kind === 1 && typeof window !== "undefined") {
        window.scroll(0, 0);
      }
      return;
    }

    await drainPlatformCommands(ptr);
  };

  const applyIncomingPorts = (implPtr, initFn, modelPtr, incomingPorts, portOpts = {}) => {
    let model = modelPtr | 0;
    const initPayload = readHandle(initFn);
    const config = initPayload?.captures?.[0] | 0;
    const updateFn = browserUpdateFn(implPtr);

    if (!updateFn || !incomingPorts) {
      return { rc: RC_SUCCESS, modelPtr: model };
    }

    for (const [portName, payload] of Object.entries(incomingPorts)) {
      const handler = incomingPortHandlers.get(portName);
      if (!handler) {
        continue;
      }

      const payloadPtr = payload | 0;
      const stablePayload = cloneIncomingPortPayload(payloadPtr);
      const msgResult = invokeIncomingHandler(handler, stablePayload);
      if (msgResult.rc !== RC_SUCCESS) {
        if (stablePayload !== payloadPtr) release(stablePayload);
        return { rc: msgResult.rc, modelPtr: model };
      }

      const platformMsg = wrapIncomingPlatformMsg(msgResult.value);
      const wrappedPlatformMsg = platformMsg !== msgResult.value;
      const updateResult = invokeClosure(updateFn, [platformMsg, model]);
      if (updateResult.rc !== RC_SUCCESS) {
        if (stablePayload !== payloadPtr) release(stablePayload);
        if (wrappedPlatformMsg) {
          release(platformMsg);
        }
        return { rc: updateResult.rc, modelPtr: model };
      }

      const updatePayload = readHandle(updateResult.value);
      if (updatePayload?.tag === TAG_TUPLE2) {
        const { modelPtr: nextModelPtr, sideEffectPtr } = readPlatformUpdateTuple(updatePayload);
        model = nextModelPtr | 0;
        void drainPlatformSideEffect(sideEffectPtr);
      }

      // Deep valueReaches after each port update can be O(model). Browser first
      // paint skips it (`omitPortRcWalk`); Node probes keep the walk by default.
      if (!portOpts.omitPortRcWalk) {
        if (stablePayload !== payloadPtr && !valueReaches(model, stablePayload)) {
          release(stablePayload);
        }
        if (wrappedPlatformMsg && !valueReaches(model, platformMsg)) {
          release(platformMsg);
        }
      }
    }

    return { rc: RC_SUCCESS, modelPtr: model };
  };

  const bootBrowserProgram = (programPtr, opts = {}) => {
    const phases = {};
    const mark = (name, start) => {
      phases[name] = +(performance.now() - start).toFixed(2);
    };

    let t = performance.now();
    const program = readHandle(programPtr);
    if (program?.tag !== TAG_BROWSER_PROGRAM) {
      return { rc: RC_ERR_UNIMPLEMENTED, value: 0, innerText: "", stage: "program", phases };
    }

    const implPtr = program.impl | 0;
    const impl = readHandle(implPtr);
    if (impl?.tag !== TAG_RECORD) {
      return { rc: RC_ERR_UNIMPLEMENTED, value: 0, innerText: "", stage: "impl", phases };
    }

    const fieldCount = impl.fields?.length ?? 0;
    const initFn = recordField(implPtr, 0);
    const viewFn = browserViewFn(implPtr);
    const defaults = createDefaultBootInputs();
    const flags = opts.flags ?? defaults.flags;
    const url = opts.url ?? defaults.url;
    const key = opts.key ?? defaults.key;
    mark("setup", t);

    t = performance.now();
    const initArgs = fieldCount >= 6 ? [flags, url, key] : [flags];
    const initResult = invokeClosure(initFn, initArgs);
    mark("init", t);
    if (initResult.rc !== RC_SUCCESS) {
      return { rc: initResult.rc, value: 0, innerText: "", stage: "init", phases };
    }

    const initPayload = readHandle(initResult.value);
    let modelPtr =
      initPayload?.tag === TAG_TUPLE2 ? initPayload.first | 0 : initResult.value | 0;
    const initCmdPtr =
      initPayload?.tag === TAG_TUPLE2 ? initPayload.second | 0 : 0;

    t = performance.now();
    const subResult = registerSubscriptions(implPtr, initFn, modelPtr);
    mark("subscriptions", t);
    if (subResult.rc !== RC_SUCCESS) {
      return { rc: subResult.rc, value: 0, innerText: "", stage: "subscriptions", phases };
    }

    if (opts.incomingPorts) {
      t = performance.now();
      const applied = applyIncomingPorts(implPtr, initFn, modelPtr, opts.incomingPorts, {
        omitPortRcWalk: opts.omitPortRcWalk === true,
      });
      mark("incoming_port", t);
      if (applied.rc !== RC_SUCCESS) {
        return { rc: applied.rc, value: 0, innerText: "", stage: "incoming_port", phases };
      }
      modelPtr = applied.modelPtr | 0;

      // elm-pages registers pageDataFromJs on the Err branch; after the boot port
      // promotes pageData to Ok, re-resolve subscriptions so app subs + ports match.
      if (isElmPagesPlatformProgram()) {
        t = performance.now();
        const subAfterPort = registerSubscriptions(implPtr, initFn, modelPtr);
        mark("subscriptions_after_port", t);
        if (subAfterPort.rc !== RC_SUCCESS) {
          return {
            rc: subAfterPort.rc,
            value: 0,
            innerText: "",
            stage: "subscriptions_after_port",
            phases,
          };
        }
      }
    } else {
      phases.incoming_port = 0;
      phases.subscriptions_after_port = 0;
    }

    t = performance.now();
    const modelForView = cloneHandleForProgram(modelPtr);
    mark("clone_model", t);

    t = performance.now();
    const viewResult = invokeClosure(viewFn, [modelForView]);
    mark("view", t);
    if (viewResult.rc !== RC_SUCCESS) {
      return { rc: viewResult.rc, value: 0, innerText: "", stage: "view", phases };
    }

    t = performance.now();
    mountViewHandle(viewResult.value);
    mark("mount", t);

    liveBrowser = {
      implPtr,
      modelPtr: modelForView | 0,
      updateFn: browserUpdateFn(implPtr),
      viewFn,
      mountedRoot: null,
      lastVdomPtr: 0,
    };

    if (fieldCount >= 6 && navigationRuntime) {
      navigationRuntime.installApplicationNavigation(implPtr);
    }

    void drainPlatformCommands(initCmdPtr);

    t = performance.now();
    const skipInnerText = opts.skipInnerText === true;
    const innerText = skipInnerText ? "" : vdomInnerTextFromView(viewResult.value);
    mark("inner_text", t);

    t = performance.now();
    const title = viewTitleFromView(viewResult.value);
    mark("title", t);

    return {
      rc: RC_SUCCESS,
      value: viewResult.value,
      innerText,
      title,
      initValue: initResult.value,
      modelPtr: modelForView,
      outgoingPorts: [...outgoingPortQueue],
      stage: "ok",
      phases,
    };
  };

  const drainOutgoingPorts = () => {
    const queued = [...outgoingPortQueue];
    outgoingPortQueue.length = 0;
    return queued;
  };

  const sendIncomingPort = (portName, payloadPtr) => {
    const handler = incomingPortHandlers.get(String(portName));
    if (!handler) {
      return { rc: RC_ERR_UNIMPLEMENTED, value: 0 };
    }
    const stablePayload = cloneIncomingPortPayload(payloadPtr | 0);
    const result = invokeIncomingHandler(handler, stablePayload);
    if (
      stablePayload !== (payloadPtr | 0) &&
      !valueReaches(result.value, stablePayload)
    ) {
      release(stablePayload);
    }
    return result;
  };

  const viewTitleFromView = (viewPtr) => {
    const payload = readHandle(viewPtr);
    if (payload?.tag === TAG_RECORD && (payload.fields?.length ?? 0) >= 1) {
      const { titlePtr } = viewTitleAndBodyFields(payload);
      return stringValue(titlePtr);
    }
    return "";
  };

  const vdomInnerTextFromView = (viewPtr) => {
    const payload = readHandle(viewPtr);
    if (payload?.tag === TAG_RECORD && (payload.fields?.length ?? 0) >= 2) {
      const { bodyPtr } = viewTitleAndBodyFields(payload);
      return listItems(bodyPtr)
        .map((child) => vdomInnerText(resolveHtml(asHandle(child))))
        .join("");
    }
    return vdomInnerText(viewPtr);
  };

  const isBrowserProgram = (ptr) => readHandle(ptr)?.tag === TAG_BROWSER_PROGRAM;

  const cmdNoneHandle = () => newIntHandle(0);

  const asHandle = (ptr) => {
    if (!ptr) return newIntHandle(0);
    if (handles.has(ptr)) return ptr;
    return newIntHandle(intValue(ptr));
  };

  const wasmScalarArg = (ptr) => {
    if (!handles.has(ptr)) return ptr | 0;
    const payload = handles.get(ptr);
    // WASM may pass constructor tags / browser_cmd kinds as raw i32.const N that
    // collide with early immortal Int handles (UNIT is handle 1 = Int 0).
    if (
      payload?.tag === TAG_INT &&
      payload.immortal &&
      ptr <= 255 &&
      (payload.value | 0) !== ptr
    ) {
      return ptr | 0;
    }
    return intValue(ptr);
  };

  const retain = (outPtr, handlePtr) => {
    const handle = handlePtr ?? outPtr;
    if (!outPtr && handle && handles.has(handle)) {
      const payload = handles.get(handle);
      payload.rc = (payload.rc ?? 1) + 1;
      retainCount += 1;
    }

    if (outPtr) {
      if (!handles.has(handlePtr)) {
        writeOut(outPtr, newIntHandle(wasmScalarArg(handlePtr)));
      } else {
        const payload = handles.get(handlePtr);
        if (payload?.tag === TAG_INT) {
          writeOut(outPtr, newIntHandle(payload.value));
        } else {
          // Mirror C elmc_retain: an out-slot alias shares ownership and must bump rc.
          if (!payload?.immortal) {
            payload.rc = (payload.rc ?? 1) + 1;
            retainCount += 1;
          }
          writeOut(outPtr, handlePtr);
        }
      }
    }

    return RC_SUCCESS;
  };

  const valueReaches = (rootPtr, targetPtr, seen = null) => {
    const root = rootPtr | 0;
    const target = targetPtr | 0;
    if (!target) return false;
    if (!root) return false;
    if (root === target) return true;

    const visited = seen ?? new Set();
    if (visited.has(root)) return false;
    visited.add(root);

    const payload = readHandle(root);
    if (!payload) return false;

    switch (payload.tag) {
      case TAG_TUPLE2:
        return (
          valueReaches(payload.first | 0, target, visited) ||
          valueReaches(payload.second | 0, target, visited)
        );
      case TAG_RECORD:
        return (payload.fields ?? []).some((field) => valueReaches(field | 0, target, visited));
      case TAG_LIST:
        return (payload.items ?? []).some((item) => valueReaches(item | 0, target, visited));
      case TAG_MAYBE:
        return payload.value != null && valueReaches(payload.value | 0, target, visited);
      case TAG_RESULT:
        return payload.value != null && valueReaches(payload.value | 0, target, visited);
      case TAG_CLOSURE:
        return (payload.captures ?? []).some((capture) =>
          valueReaches(capture | 0, target, visited)
        );
      case TAG_VDOM:
        if (payload.kind === "node") {
          return (payload.children ?? []).some((child) => valueReaches(child | 0, target, visited));
        }
        if (payload.kind === "map") {
          return valueReaches(payload.child | 0, target, visited);
        }
        return false;
      case TAG_BROWSER_PROGRAM:
        return payload.impl != null && valueReaches(payload.impl | 0, target, visited);
      default:
        return false;
    }
  };

  const currentCallRoots = () =>
    callRootStack.length > 0 ? callRootStack[callRootStack.length - 1] : [];

  // Epilogue calls `release_unless_reachable_from_roots` once per owned slot with the
  // same root list. Mark-by-generation once per fingerprint turns O(n·|graph|) into
  // O(|graph| + n) without allocating a Set on every epilogue.
  let reachableCache = {
    fingerprint: null,
    gen: 0,
  };
  let reachGen = 1;

  const invalidateReachableCache = () => {
    reachableCache.fingerprint = null;
    reachableCache.gen = 0;
  };

  const pushCallRoots = (...roots) => {
    const normalized = roots
      .flat()
      .map((ptr) => ptr | 0)
      .filter((ptr) => ptr !== 0 && handles.has(ptr));
    callRootStack.push(normalized);
    invalidateReachableCache();
  };

  const popCallRoots = () => {
    callRootStack.pop();
    invalidateReachableCache();
  };

  const markReachable = (rootPtr, gen) => {
    const stack = [rootPtr | 0];
    while (stack.length > 0) {
      const root = stack.pop() | 0;
      if (!root) continue;
      const payload = handles.get(root);
      if (!payload || payload._rg === gen) continue;
      payload._rg = gen;
      switch (payload.tag) {
        case TAG_TUPLE2:
          stack.push(payload.first | 0, payload.second | 0);
          break;
        case TAG_RECORD:
          for (const field of payload.fields ?? []) stack.push(field | 0);
          break;
        case TAG_LIST:
          for (const item of payload.items ?? []) stack.push(item | 0);
          break;
        case TAG_MAYBE:
        case TAG_RESULT:
          if (payload.value != null) stack.push(payload.value | 0);
          break;
        case TAG_CLOSURE:
          for (const capture of payload.captures ?? []) stack.push(capture | 0);
          for (const applied of payload.applied ?? []) stack.push(applied | 0);
          break;
        case TAG_VDOM:
          if (payload.kind === "node") {
            for (const child of payload.children ?? []) stack.push(child | 0);
          } else if (payload.kind === "map") {
            stack.push(payload.child | 0);
          }
          break;
        case TAG_BROWSER_PROGRAM:
          if (payload.impl != null) stack.push(payload.impl | 0);
          break;
        default:
          break;
      }
    }
  };

  const rootsFingerprint = (rootsPtr, count) => {
    let h = (count | 0) ^ ((callRootStack.length | 0) << 16);
    const total = count | 0;
    const base = rootsPtr | 0;
    if (memory && total > 0 && base) {
      for (let i = 0; i < total; i++) {
        h = (Math.imul(h, 31) + (view().getUint32(base + i * 4, true) | 0)) | 0;
      }
    }
    for (const callRoot of currentCallRoots()) {
      h = (Math.imul(h, 31) + (callRoot | 0)) | 0;
    }
    return h;
  };

  let reachCacheHits = 0;
  let reachCacheMisses = 0;

  const ensureReachableGen = (rootsPtr, count) => {
    const fingerprint = rootsFingerprint(rootsPtr, count);
    if (reachableCache.gen && reachableCache.fingerprint === fingerprint) {
      reachCacheHits += 1;
      return reachableCache.gen;
    }
    reachCacheMisses += 1;

    reachGen += 1;
    if (reachGen > 1_000_000_000) {
      reachGen = 1;
      for (const payload of handles.values()) {
        if (payload) payload._rg = 0;
      }
    }
    const gen = reachGen;
    const total = count | 0;
    const base = rootsPtr | 0;
    if (memory && total > 0 && base) {
      for (let i = 0; i < total; i++) {
        markReachable(view().getUint32(base + i * 4, true) | 0, gen);
      }
    }
    for (const callRoot of currentCallRoots()) {
      markReachable(callRoot, gen);
    }

    reachableCache = { fingerprint, gen };
    return gen;
  };

  const isReachableFromRoots = (handle, rootPtr) => {
    const root = rootPtr | 0;
    if (root && valueReaches(root, handle)) {
      return true;
    }

    for (const callRoot of currentCallRoots()) {
      if (valueReaches(callRoot, handle)) {
        return true;
      }
    }

    return false;
  };

  const isReachableFromRootList = (handle, rootsPtr, count) => {
    const h = handle | 0;
    const total = count | 0;
    const base = rootsPtr | 0;
    // Fast path: owned slot often aliases *out / a param handle directly.
    if (memory && total > 0 && base) {
      for (let i = 0; i < total; i++) {
        if ((view().getUint32(base + i * 4, true) | 0) === h) {
          return true;
        }
      }
    }
    for (const callRoot of currentCallRoots()) {
      if (callRoot === h) {
        return true;
      }
    }
    const gen = ensureReachableGen(rootsPtr, count);
    const payload = handles.get(h);
    return Boolean(payload && payload._rg === gen);
  };

  const releaseUnlessReachableFromRoots = (ptr, rootsPtr, count) => {
    const handle = ptr | 0;
    if (!handle || !handles.has(handle)) {
      return RC_SUCCESS;
    }

    const payload = handles.get(handle);
    if (payload?.immortal) {
      return RC_SUCCESS;
    }

    if (isReachableFromRootList(handle, rootsPtr, count)) {
      return RC_SUCCESS;
    }

    const fallbackRoot = memory ? view().getUint32(rootsPtr | 0, true) | 0 : 0;
    releaseValue(handle, fallbackRoot);
    return RC_SUCCESS;
  };

  const SINGLE_ROOT_SCRATCH = 16384;

  const releaseUnlessReachable = (ptr, rootPtr) => {
    if (!memory) {
      return releaseUnlessReachableFromRoots(ptr, 0, 0);
    }
    // Do not write into 4096 — that scratch holds the multi-root epilogue list.
    view().setUint32(SINGLE_ROOT_SCRATCH, rootPtr | 0, true);
    return releaseUnlessReachableFromRoots(ptr, SINGLE_ROOT_SCRATCH, 1);
  };

  const releaseChild = (childPtr, rootPtr) => {
    const child = childPtr | 0;
    if (!child || !handles.has(child)) {
      return;
    }

    if (rootPtr) {
      // Prefer O(1) against the epilogue reach generation so cascading frees don't
      // re-walk the graph (and don't clobber the multi-root scratch at 4096).
      if (reachableCache.gen) {
        const payload = handles.get(child);
        if (payload && payload._rg === reachableCache.gen) {
          return;
        }
        release(child);
        return;
      }
      releaseUnlessReachable(child, rootPtr);
    } else {
      release(child);
    }
  };

  const releaseValue = (ptr, rootPtr) => {
    if (!ptr || !handles.has(ptr)) {
      return RC_SUCCESS;
    }

    const payload = handles.get(ptr);

    if (payload?.immortal) {
      return RC_SUCCESS;
    }

    payload.rc = (payload.rc ?? 1) - 1;
    if (payload.rc > 0) {
      return RC_SUCCESS;
    }

    if (payload?.tag === TAG_CLOSURE) {
      for (const capture of payload.captures ?? []) {
        releaseChild(capture, rootPtr);
      }
    }

    if (payload?.tag === TAG_MAYBE && payload.value && handles.has(payload.value)) {
      releaseChild(payload.value, rootPtr);
    }

    if (payload?.tag === TAG_RESULT && payload.value && handles.has(payload.value)) {
      releaseChild(payload.value, rootPtr);
    }

    if (payload?.tag === TAG_LIST) {
      for (const item of payload.items ?? []) {
        releaseChild(item, rootPtr);
      }
    }

    if (payload?.tag === TAG_TUPLE2) {
      releaseChild(payload.first, rootPtr);
      releaseChild(payload.second, rootPtr);
    }

    if (payload?.tag === TAG_RECORD) {
      for (const field of payload.fields ?? []) {
        releaseChild(field, rootPtr);
      }
    }

    if (payload?.tag === TAG_VDOM && payload.kind === "node") {
      for (const child of payload.children ?? []) {
        releaseChild(child, rootPtr);
      }
    }

    if (payload?.tag === TAG_VDOM && payload.kind === "map") {
      releaseChild(payload.child, rootPtr);
    }

    if (payload?.tag === TAG_VDOM && payload.kind === "text") {
      // leaf text payload
    }

    if (payload?.tag === TAG_VDOM && payload.kind === "attr") {
      // leaf attr payload
    }

    if (payload?.tag === TAG_BROWSER_PROGRAM) {
      if (payload.impl && handles.has(payload.impl)) {
        releaseChild(payload.impl, rootPtr);
      }
    }

    handles.delete(ptr);
    retainCount = Math.max(0, retainCount - 1);
    return RC_SUCCESS;
  };

  const release = (ptr) => releaseValue(ptr, null);

  const detachTupleSecond = (tuplePtr) => {
    const stored = handles.get(tuplePtr | 0);
    if (stored?.tag !== TAG_TUPLE2) return 0;
    const second = stored.second | 0;
    stored.second = 0;
    return second;
  };

  const releaseArrayLifo = (basePtr, count) => {
    for (let i = count - 1; i >= 0; i--) {
      const slotPtr = basePtr + i * 4;
      const handle = view().getUint32(slotPtr, true);
      release(handle);
    }
    return RC_SUCCESS;
  };

  const asFloatBits = (ptr) => {
    if (!ptr) return 0;
    const payload = handles.get(ptr);
    if (!payload) return 0;

    const buf = new ArrayBuffer(4);
    const view = new DataView(buf);
    const value =
      payload.tag === TAG_FLOAT ? payload.value : payload.tag === TAG_INT ? payload.value : 0;
    view.setFloat32(0, value, true);
    return view.getUint32(0, true) | 0;
  };

  const floatDivBits = (leftBits, rightBits) => {
    const buf = new ArrayBuffer(4);
    const view = new DataView(buf);
    view.setUint32(0, leftBits >>> 0, true);
    const left = view.getFloat32(0, true);
    view.setUint32(0, rightBits >>> 0, true);
    const right = view.getFloat32(0, true);
    view.setFloat32(0, left / right, true);
    return view.getUint32(0, true) | 0;
  };

  const applyDomAttr = (el, attr, mapperPtr = 0) => {
    if (!el || !attr) return;
    if (attr.kind === "event") {
      attachDomEvent(el, attr, mapperPtr);
      return;
    }
    if (attr.kind === "property") {
      const prop = attr.name;
      if (prop === "value" || prop === "checked" || prop === "selected" || prop === "disabled") {
        el[prop] = attr.value;
      } else {
        el[prop] = attr.value;
      }
      return;
    }
    if (attr.name === "style") {
      el.setAttribute("style", attr.value);
    } else if (attr.name === "class") {
      el.className = attr.value;
    } else if (attr.name) {
      el.setAttribute(attr.name, attr.value);
    }
  };

  const newVdomAttr = (name, value) =>
    allocHandle({ tag: TAG_VDOM, kind: "attr", name: String(name), value: String(value) });

  const newVdomProperty = (name, value) =>
    allocHandle({ tag: TAG_VDOM, kind: "property", name: String(name), value: String(value) });

  const newVdomEvent = (eventName, handlerPtr, decoderPtr = 0) =>
    allocHandle({
      tag: TAG_VDOM,
      kind: "event",
      event: String(eventName),
      handler: handlerPtr | 0,
      decoder: decoderPtr | 0,
    });

  const newVdomNode = (tagName, attrs, children, namespace = null, keyedChildren = null) =>
    allocHandle({
      tag: TAG_VDOM,
      kind: "node",
      tagName: String(tagName),
      namespace: namespace ? String(namespace) : null,
      attrs: attrs ?? [],
      children: children ?? [],
      keyedChildren: keyedChildren ?? null,
    });

  const vdomAttrs = (attrs) =>
    (attrs ?? [])
      .map((entry) => {
        if (!entry || typeof entry !== "object") return null;
        if (entry.name != null && entry.value != null) return { name: entry.name, value: entry.value };
        return null;
      })
      .filter(Boolean);

  const keyedChildrenFromList = (keyedPtr) =>
    listItems(keyedPtr)
      .map((entryPtr) => {
        const pair = readHandle(entryPtr);
        if (pair?.tag === TAG_TUPLE2) {
          return { key: stringValue(pair.first | 0), child: adoptVdom(pair.second | 0) };
        }
        return { key: "", child: adoptVdom(entryPtr) };
      })
      .filter((entry) => entry.child);

  const attrsFromList = (listPtr) =>
    listItems(listPtr)
      .map((item) => {
        const payload = readHandle(asHandle(item));
        if (payload?.tag === TAG_VDOM && payload.kind === "attr") {
          return { name: payload.name, value: payload.value };
        }
        if (payload?.tag === TAG_VDOM && payload.kind === "property") {
          return { kind: "property", name: payload.name, value: payload.value };
        }
        if (payload?.tag === TAG_VDOM && payload.kind === "event") {
          return {
            kind: "event",
            event: payload.event,
            handler: payload.handler,
            decoder: payload.decoder,
          };
        }
        return null;
      })
      .filter(Boolean);

  const newVdomText = (text) => allocHandle({ tag: TAG_VDOM, kind: "text", text: String(text) });

  const inspectVdom = (ptr) => {
    const resolved = resolveHtml(asHandle(ptr));
    const payload = readHandle(resolved);
    if (!payload || payload.tag !== TAG_VDOM) return null;
    if (payload.kind === "text") return { kind: "text", text: payload.text };
    if (payload.kind === "node") {
      return {
        kind: "node",
        tagName: payload.tagName,
        childCount: (payload.children ?? []).length,
        innerText: vdomInnerText(resolveHtml(asHandle(ptr))),
        attrs: vdomAttrs(payload.attrs),
      };
    }
    if (payload.kind === "attr") {
      return { kind: "attr", name: payload.name, value: payload.value };
    }
    return { kind: payload.kind ?? "unknown" };
  };

  const vdomInnerText = (ptr) => {
    const payload = readHandle(ptr);
    if (!payload || payload.tag !== TAG_VDOM) return "";
    if (payload.kind === "text") return payload.text;
    if (payload.kind === "node") {
      return (payload.children ?? [])
        .map((child) => vdomInnerText(child))
        .join("");
    }
    return "";
  };

  const cloneVdom = (ptr) => {
    const payload = readHandle(ptr);
    if (!payload || payload.tag !== TAG_VDOM) {
      return ptr;
    }

    if (payload.kind === "map") {
      return cloneVdom(payload.child | 0);
    }

    if (payload.kind === "text") {
      return newVdomText(payload.text);
    }

    if (payload.kind === "attr") {
      return newVdomAttr(payload.name, payload.value);
    }

    if (payload.kind === "node") {
      return newVdomNode(
        payload.tagName,
        payload.attrs ?? [],
        (payload.children ?? []).map((child) => cloneVdom(child))
      );
    }

    return ptr;
  };

  /** Prefer share+retain over deep clone when adopting VDOM into a parent. */
  const adoptVdom = (ptr) => {
    const resolved = resolveHtml(asHandle(ptr));
    if (!resolved || !handles.has(resolved)) return resolved | 0;
    const payload = readHandle(resolved);
    if (payload?.tag === TAG_VDOM) {
      retain(null, resolved);
      return resolved | 0;
    }
    return resolved | 0;
  };

  const ensureAppRoot = () => {
    if (typeof document === "undefined") {
      return null;
    }

    let root = document.getElementById("app");
    if (!root) {
      root = document.createElement("div");
      root.id = "app";
      document.body.appendChild(root);
    }
    return root;
  };

  const dispatchPlatformMsg = (msgPtr) => {
    if (!liveBrowser || !msgPtr) return;
    const { implPtr, modelPtr, updateFn, viewFn } = liveBrowser;
    const platformMsg = wrapIncomingPlatformMsg(msgPtr | 0);
    const updateResult = invokeClosure(updateFn, [platformMsg, modelPtr | 0]);
    if (updateResult.rc !== RC_SUCCESS) {
      return;
    }
    const updatePayload = readHandle(updateResult.value);
    if (updatePayload?.tag === TAG_TUPLE2) {
      const { modelPtr: nextModelPtr, sideEffectPtr } = readPlatformUpdateTuple(updatePayload);
      liveBrowser.modelPtr = nextModelPtr | 0;
      void drainPlatformSideEffect(sideEffectPtr);
    }
    const viewResult = invokeClosure(viewFn, [liveBrowser.modelPtr | 0]);
    if (viewResult.rc === RC_SUCCESS) {
      mountViewHandle(viewResult.value);
    }
  };
  dispatchPlatformMsgRef = dispatchPlatformMsg;

  const vdomToDom = (ptr, mapperPtr = 0) => {
    const payload = readHandle(resolveHtml(ptr));
    if (!payload || payload.tag !== TAG_VDOM) {
      return typeof document !== "undefined" ? document.createTextNode("") : null;
    }

    if (payload.kind === "text") {
      return typeof document !== "undefined" ? document.createTextNode(payload.text) : null;
    }

    if (payload.kind === "map" && typeof document !== "undefined") {
      return vdomToDom(payload.child | 0, payload.mapper | 0);
    }

    if (payload.kind === "lazy") {
      const forced = forceLazyHtml(ptr);
      if (forced.rc === RC_SUCCESS && forced.value) {
        return vdomToDom(forced.value, mapperPtr);
      }
      return typeof document !== "undefined" ? document.createTextNode("") : null;
    }

    if (payload.kind === "node" && typeof document !== "undefined") {
      const el = payload.namespace
        ? document.createElementNS(payload.namespace, payload.tagName || "div")
        : document.createElement(payload.tagName || "div");
      let styleText = "";
      for (const attr of payload.attrs ?? []) {
        applyDomAttr(el, attr, mapperPtr);
        if (attr?.name === "style" && attr.kind !== "event" && attr.kind !== "property") {
          styleText += attr.value;
        }
      }
      if (styleText) el.setAttribute("style", styleText);
      if (payload.keyedChildren?.length) {
        for (const { key, child } of payload.keyedChildren) {
          const childDom = vdomToDom(child, mapperPtr);
          if (childDom) {
            childDom.__vdomKey = String(key);
            el.appendChild(childDom);
          }
        }
      } else {
        for (const child of payload.children ?? []) {
          const childDom = vdomToDom(child, mapperPtr);
          if (childDom) el.appendChild(childDom);
        }
      }
      return el;
    }

    return typeof document !== "undefined" ? document.createTextNode("") : null;
  };

  const attachDomEvent = (el, eventAttr, mapperPtr = 0) => {
    const eventName = eventAttr.event || "click";
    const handlerPtr = eventAttr.handler | 0;
    const decoderPtr = eventAttr.decoder | 0;
    const listener = (domEvent) => {
      if (eventName === "submit" && typeof domEvent.preventDefault === "function") {
        domEvent.preventDefault();
      }
      let msgPtr = 0;
      if (decoderPtr) {
        const eventValue = domEventRuntime
          ? domEventRuntime.buildDecoderArg(domEvent, eventName)
          : newIntHandle(domEvent?.target?.value ? 1 : 0);
        const decoded = invokeClosure(decoderPtr, [eventValue]);
        if (decoded.rc !== RC_SUCCESS) return;
        msgPtr = decoded.value | 0;
      } else if (handlerPtr) {
        const invoked = invokeClosure(handlerPtr, []);
        if (invoked.rc !== RC_SUCCESS) return;
        msgPtr = invoked.value | 0;
      }
      if (mapperPtr) {
        const mapped = invokeClosure(mapperPtr, [asHandle(msgPtr)]);
        if (mapped.rc !== RC_SUCCESS) return;
        msgPtr = mapped.value | 0;
      }
      if (msgPtr) dispatchPlatformMsg(msgPtr);
    };
    el.addEventListener(eventName, listener);
    return listener;
  };

  const mountVdomToApp = (ptr) => {
    if (typeof document === "undefined") return;
    const root = ensureAppRoot();
    if (!root) return;
    root.replaceChildren();
    const dom = vdomToDom(ptr);
    if (dom) root.appendChild(dom);
  };

  const listItems = (ptr) => {
    if (!ptr) return [];
    const payload = readHandle(ptr);
    if (!payload) return [];
    if (payload.tag === TAG_LIST) return payload.items ?? [];
    if (payload.tag === TAG_TUPLE2) {
      const items = [];
      let cur = ptr | 0;
      while (cur) {
        const cell = readHandle(cur);
        if (cell?.tag !== TAG_TUPLE2) break;
        items.push(cell.first | 0);
        cur = cell.second | 0;
      }
      return items;
    }
    return [];
  };

  const listItemsForAppend = (ptr) => {
    if (!ptr) return [];
    const payload = readHandle(ptr);
    if (!payload) return [];
    if (payload.tag === TAG_STRING) return [ptr | 0];
    return listItems(ptr);
  };

  const newInt = (outPtr, value) => {
    writeOut(outPtr, allocHandle({ tag: TAG_INT, value: value | 0 }));
    return RC_SUCCESS;
  };

  const newBool = (outPtr, value) => {
    writeOut(outPtr, allocHandle({ tag: TAG_INT, value: value ? 1 : 0 }));
    return RC_SUCCESS;
  };

  const newFloat = (outPtr, bits) => {
    const buf = new ArrayBuffer(4);
    const view = new DataView(buf);
    view.setUint32(0, bits >>> 0, true);
    const value = view.getFloat32(0, true);
    writeOut(outPtr, allocHandle({ tag: TAG_FLOAT, value }));
    return RC_SUCCESS;
  };

  const newList = (items) => allocHandle({ tag: TAG_LIST, items: [...items] });

  const writeList = (outPtr, items) => {
    writeOut(outPtr, newList(items));
    return RC_SUCCESS;
  };

  const listNil = (outPtr) => writeList(outPtr, []);

  const listFromIntArray = (outPtr, itemsPtr, count) => {
    const items = [];
    for (let i = 0; i < count; i++) {
      items.push(view().getInt32(itemsPtr + i * 4, true));
    }
    return writeList(outPtr, items);
  };

  const cloneForList = (ptr) => {
    if (!ptr || !handles.has(ptr)) return ptr;
    // Take ownership share of list elements so epilogue can release builders safely.
    retain(null, ptr);
    return ptr;
  };

  const listFromValues = (outPtr, arrayPtr, count) => {
    const items = [];
    for (let i = 0; i < count; i++) {
      items.push(cloneForList(view().getUint32(arrayPtr + i * 4, true)));
    }
    writeOut(outPtr, allocHandle({ tag: TAG_LIST, items }));
    return RC_SUCCESS;
  };

  const listLength = (outPtr, listPtr) => newInt(outPtr, listItems(listPtr).length);

  const listSum = (outPtr, listPtr) => {
    const sum = listItems(listPtr).reduce((a, b) => a + b, 0);
    return newInt(outPtr, sum);
  };

  const listProduct = (outPtr, listPtr) => {
    const items = listItems(listPtr);
    const product = items.length === 0 ? 0 : items.reduce((a, b) => a * b, 1);
    return newInt(outPtr, product);
  };

  const listReverse = (outPtr, listPtr) =>
    writeList(outPtr, [...listItems(listPtr)].reverse().map(cloneForList));

  const listAppend = (outPtr, leftPtr, rightPtr) =>
    writeList(outPtr, [
      ...listItemsForAppend(leftPtr).map(cloneForList),
      ...listItemsForAppend(rightPtr).map(cloneForList),
    ]);

  const listConcat = (outPtr, listsPtr) => {
    const items = [];
    for (const innerHandle of listItems(listsPtr)) {
      for (const item of listItems(innerHandle)) {
        items.push(cloneForList(item));
      }
    }
    return writeList(outPtr, items);
  };

  const listMember = (outPtr, valuePtr, listPtr) => {
    const needle = asHandle(valuePtr);
    const found = listItems(listPtr).some((item) => valuesEqual(asHandle(item), needle));
    return newInt(outPtr, found ? 1 : 0);
  };

  const listIsEmpty = (outPtr, listPtr) => newInt(outPtr, listItems(listPtr).length === 0 ? 1 : 0);

  const listHead = (outPtr, listPtr) => {
    const items = listItems(listPtr);
    if (items.length === 0) return maybeNothing(outPtr);
    const first = items[0] | 0;
    if (handles.has(first)) {
      return maybeJust(outPtr, first);
    }
    return maybeJustOwn(outPtr, newIntHandle(first));
  };

  const listTail = (outPtr, listPtr) => {
    const items = listItems(listPtr);
    if (items.length === 0) return maybeNothing(outPtr);
    return maybeJustOwn(outPtr, newList(items.slice(1)));
  };

  const listTake = (outPtr, countPtr, listPtr) => {
    const count = intValue(countPtr);
    return writeList(outPtr, listItems(listPtr).slice(0, count));
  };

  const listDrop = (outPtr, countPtr, listPtr) => {
    const count = intValue(countPtr);
    return writeList(outPtr, listItems(listPtr).slice(count));
  };

  const listRange = (outPtr, startPtr, endPtr) => {
    const low = asIntNumber(startPtr);
    const high = asIntNumber(endPtr);
    const items = [];
    // Match C elmc_list_range / Elm List.range: inclusive on both ends, high -> low.
    for (let i = high; i >= low; i--) items.push(i);
    return writeList(outPtr, items);
  };

  const listRepeat = (outPtr, valuePtr, countPtr) => {
    const value = intValue(valuePtr);
    const count = intValue(countPtr);
    return writeList(outPtr, Array.from({ length: count }, () => value));
  };

  const listSingleton = (outPtr, valuePtr) => {
    if (handles.has(valuePtr | 0)) {
      return writeList(outPtr, [cloneForList(valuePtr)]);
    }
    return writeList(outPtr, [intValue(valuePtr)]);
  };

  // Match C elmc_list_cons(take=0): retain spine elements so callers can release consumed args.
  const listCons = (outPtr, headPtr, tailPtr) => {
    const head = handles.has(headPtr | 0) ? cloneForList(headPtr) : intValue(headPtr);
    const tail = listItems(tailPtr).map(cloneForList);
    return writeList(outPtr, [head, ...tail]);
  };

  const listMaximum = (outPtr, listPtr) => {
    const items = listItems(listPtr);
    if (items.length === 0) return maybeNothing(outPtr);
    let best = items[0] | 0;
    for (let i = 1; i < items.length; i++) {
      const item = items[i] | 0;
      if (compareValues(item, best) > 0) best = item;
    }
    return maybeJust(outPtr, best);
  };

  const listMinimum = (outPtr, listPtr) => {
    const items = listItems(listPtr);
    if (items.length === 0) return maybeNothing(outPtr);
    let best = items[0] | 0;
    for (let i = 1; i < items.length; i++) {
      const item = items[i] | 0;
      if (compareValues(item, best) < 0) best = item;
    }
    return maybeJust(outPtr, best);
  };

  const listIntersperse = (outPtr, sepPtr, listPtr) => {
    const sep = intValue(sepPtr);
    const items = listItems(listPtr);
    if (items.length === 0) return writeList(outPtr, []);
    const out = [items[0]];
    for (let i = 1; i < items.length; i++) {
      out.push(sep, items[i]);
    }
    return writeList(outPtr, out);
  };

  const listSort = (outPtr, listPtr) =>
    writeList(outPtr, [...listItems(listPtr)].sort((a, b) => a - b));

  const compareInts = (a, b) => (a < b ? -1 : a > b ? 1 : 0);

  const isMaybeNothing = (ptr) => {
    const handle = ptr | 0;
    if (!handle) return true;
    const payload = readHandle(handle);
    if (!payload) return true;
    if (payload.tag === TAG_MAYBE) return payload.value == null;
    if (payload.tag === TAG_INT) return intValue(handle) === 0;
    return false;
  };

  // Some WASM paths return a bare union `(tag, payload)` tuple where Elm expects
  // `Maybe` (for example `Route.urlToRoute` metadata stored in a `Maybe Route` field).
  const maybePayloadHandle = (ptr) => {
    const handle = ptr | 0;
    if (!handle) return null;
    const payload = readHandle(handle);
    if (!payload) return null;
    if (payload.tag === TAG_MAYBE) {
      return payload.value != null ? payload.value | 0 : null;
    }
    if (payload.tag === TAG_TUPLE2) {
      return handle;
    }
    return null;
  };

  const writeMaybeFromValue = (outPtr, valuePtr) => {
    const value = valuePtr | 0;
    if (!value) return maybeNothing(outPtr);
    const payload = readHandle(value);
    if (payload?.tag === TAG_MAYBE) {
      writeOut(outPtr, value);
      retain(null, value);
      return RC_SUCCESS;
    }
    const rc = maybeJust(outPtr, value);
    if (handles.has(value)) release(value);
    return rc;
  };

  const maybeJustInt = (ptr) => {
    const payload = readHandle(ptr);
    if (payload?.tag === TAG_MAYBE && payload.value != null) {
      return intValue(payload.value);
    }
    return null;
  };

  const maybeJustPayloadHandle = (ptr) => {
    const payload = readHandle(ptr);
    if (payload?.tag === TAG_MAYBE && payload.value != null) {
      return payload.value | 0;
    }
    return null;
  };

  const listSortWith = (outPtr, cmpClosurePtr, listPtr) => {
    const items = [...listItems(listPtr)];
    items.sort((left, right) => {
      const argA = asHandle(left);
      const argB = asHandle(right);
      const { rc, value } = invokeClosure(cmpClosurePtr, [argA, argB]);
      if (rc !== RC_SUCCESS) return 0;
      const order = intValue(value);
      release(value);
      return order;
    });
    return writeList(outPtr, items);
  };

  const listSortBy = (outPtr, keyClosurePtr, listPtr) => {
    const items = listItems(listPtr);
    const keyed = items.map((item) => {
      const arg = asHandle(item);
      const { rc, value } = invokeClosure(keyClosurePtr, [arg]);
      if (rc !== RC_SUCCESS) return { item, key: 0 };
      const key = intValue(value);
      release(value);
      return { item, key };
    });
    keyed.sort((left, right) => left.key - right.key);
    return writeList(
      outPtr,
      keyed.map((entry) => entry.item)
    );
  };

  const listFoldl = (outPtr, closurePtr, initHandle, listPtr) => {
    let accHandle = asHandle(initHandle);

    for (const item of listItems(listPtr)) {
      const arg = asHandle(item);
      const { rc, value } = invokeClosure(closurePtr, [arg, accHandle]);
      if (rc !== RC_SUCCESS) return rc;
      if (accHandle) release(accHandle);
      accHandle = value;
    }

    writeOut(outPtr, accHandle);
    return RC_SUCCESS;
  };

  const listFoldr = (outPtr, closurePtr, initHandle, listPtr) => {
    let accHandle = asHandle(initHandle);
    const items = listItems(listPtr);

    for (let i = items.length - 1; i >= 0; i--) {
      const arg = asHandle(items[i]);
      const { rc, value } = invokeClosure(closurePtr, [arg, accHandle]);
      if (rc !== RC_SUCCESS) return rc;
      if (accHandle) release(accHandle);
      accHandle = value;
    }

    writeOut(outPtr, accHandle);
    return RC_SUCCESS;
  };

  const listAny = (outPtr, predClosurePtr, listPtr) => {
    for (const item of listItems(listPtr)) {
      const arg = asHandle(item);
      const { rc, value } = invokeClosure(predClosurePtr, [arg]);
      if (rc !== RC_SUCCESS) return rc;
      const truthy = intValue(value) !== 0;
      release(value);
      if (truthy) return newInt(outPtr, 1);
    }

    return newInt(outPtr, 0);
  };

  const listAll = (outPtr, predClosurePtr, listPtr) => {
    const items = listItems(listPtr);
    if (items.length === 0) return newInt(outPtr, 0);

    for (const item of items) {
      const arg = asHandle(item);
      const { rc, value } = invokeClosure(predClosurePtr, [arg]);
      if (rc !== RC_SUCCESS) return rc;
      const truthy = intValue(value) !== 0;
      release(value);
      if (!truthy) return newInt(outPtr, 0);
    }

    return newInt(outPtr, 1);
  };

  const filterMapListWithClosure = (outPtr, closurePtr, listPtr) => {
    const results = [];

    for (const item of listItems(listPtr)) {
      const arg = asHandle(item);
      const { rc, value } = invokeClosure(closurePtr, [arg]);
      if (rc !== RC_SUCCESS) return rc;

      if (!isMaybeNothing(value)) {
        const mapped = maybeJustPayloadHandle(value);
        if (mapped != null) results.push(mapped);
      }

      release(value);
    }

    return writeList(outPtr, results);
  };

  const maybeNothing = (outPtr) => {
    writeOut(outPtr, allocHandle({ tag: TAG_MAYBE, value: null }));
    return RC_SUCCESS;
  };

  const maybeJustOwn = (outPtr, payloadHandle, tagPtr) => {
    const owned = handles.has(payloadHandle)
      ? payloadHandle
      : newIntHandle(intValue(asHandle(payloadHandle)));
    const ctorTag = tagPtr != null && tagPtr !== 0 ? wasmScalarArg(tagPtr) : 1;
    writeOut(
      outPtr,
      allocHandle({ tag: TAG_MAYBE, value: owned, isJust: true, ctorTag })
    );
    return RC_SUCCESS;
  };

  // Mirror C elmc_maybe_just: retain payload, then caller balances with release.
  const maybeJust = (outPtr, payloadHandle, tagPtr) => {
    retain(null, payloadHandle);
    return maybeJustOwn(outPtr, payloadHandle, tagPtr);
  };

  const maybeJustPayload = (outPtr, maybePtr) => {
    const payload = readHandle(maybePtr);
    if (payload?.tag === TAG_MAYBE && payload.value != null) {
      writeOut(outPtr, payload.value);
      retain(null, payload.value);
      return RC_SUCCESS;
    }

    if (payload?.tag === TAG_TUPLE2) {
      const tag = intValue(payload.first);
      if (tag === 1) {
        writeOut(outPtr, payload.second);
        retain(null, payload.second);
        return RC_SUCCESS;
      }
    }

    writeOut(outPtr, 0);
    return RC_SUCCESS;
  };

  const maybeIsNothing = (outPtr, maybePtr) => {
    const isNothing = isMaybeNothing(maybePtr);
    if (outPtr) view().setUint32(outPtr, isNothing ? 1 : 0, true);
    return RC_SUCCESS;
  };

  const maybeWithDefault = (outPtr, defaultPtr, maybePtr) => {
    const payload = readHandle(maybePtr);
    if (payload?.tag === TAG_MAYBE && payload.value != null) {
      return retain(outPtr, payload.value | 0);
    }
    if (payload?.tag === TAG_TUPLE2) {
      const tag = intValue(payload.first);
      if (tag === 1 && payload.second) {
        return retain(outPtr, payload.second | 0);
      }
    }
    return retain(outPtr, defaultPtr | 0);
  };

  const maybeMap = (outPtr, closurePtr, maybePtr) => {
    const justValue = maybePayloadHandle(maybePtr);
    if (justValue == null) return maybeNothing(outPtr);
    const { rc, value } = invokeClosure(closurePtr, [asHandle(justValue)]);
    if (rc !== RC_SUCCESS) return rc;
    const mapRc = maybeJust(outPtr, value);
    release(value);
    return mapRc;
  };

  const maybeMap2 = (outPtr, closurePtr, aPtr, bPtr) => {
    const aValue = maybePayloadHandle(aPtr);
    const bValue = maybePayloadHandle(bPtr);
    if (aValue == null || bValue == null) return maybeNothing(outPtr);
    const { rc, value } = invokeClosure(closurePtr, [
      asHandle(aValue),
      asHandle(bValue),
    ]);
    if (rc !== RC_SUCCESS) return rc;
    const mapRc = maybeJust(outPtr, value);
    release(value);
    return mapRc;
  };

  const maybeAndThen = (outPtr, closurePtr, maybePtr) => {
    const justValue = maybePayloadHandle(maybePtr);
    if (justValue == null) return maybeNothing(outPtr);
    const { rc, value } = invokeClosure(closurePtr, [asHandle(justValue)]);
    if (rc !== RC_SUCCESS) return rc;
    return writeMaybeFromValue(outPtr, value);
  };

  const tupleElements = (ptr) => {
    const payload = readHandle(ptr);
    if (!payload) return null;

    if (payload.tag === TAG_TUPLE2) {
      return { first: payload.first, second: payload.second, boxed: true };
    }

    if (payload.tag === TAG_LIST && payload.items.length >= 2) {
      const first = payload.items[0];
      const second = payload.items[1];
      const boxed =
        (first != null && handles.has(first | 0)) ||
        (second != null && handles.has(second | 0));
      return { first, second, boxed };
    }

    return null;
  };

  const tupleMapFirst = (outPtr, closurePtr, tuplePtr) => {
    const elements = tupleElements(tuplePtr);
    if (!elements) {
      writeOut(outPtr, tuplePtr);
      return RC_SUCCESS;
    }

    const firstArg = elements.boxed ? elements.first : newIntHandle(elements.first);
    const { rc, value } = invokeClosure(closurePtr, [firstArg]);
    if (!elements.boxed) release(firstArg);
    if (rc !== RC_SUCCESS) return rc;

    if (elements.boxed) {
      return tuple2(outPtr, value, elements.second);
    }

    const secondHandle = newIntHandle(elements.second);
    const mapRc = tuple2Ints(outPtr, value, secondHandle);
    release(value);
    release(secondHandle);
    return mapRc;
  };

  const tupleMapSecond = (outPtr, closurePtr, tuplePtr) => {
    const elements = tupleElements(tuplePtr);
    if (!elements) {
      writeOut(outPtr, tuplePtr);
      return RC_SUCCESS;
    }

    const secondArg = elements.boxed ? elements.second : newIntHandle(elements.second);
    const { rc, value } = invokeClosure(closurePtr, [secondArg]);
    if (!elements.boxed) release(secondArg);
    if (rc !== RC_SUCCESS) return rc;

    if (elements.boxed) {
      return tuple2(outPtr, elements.first, value);
    }

    const firstHandle = newIntHandle(elements.first);
    const mapRc = tuple2Ints(outPtr, firstHandle, value);
    release(firstHandle);
    release(value);
    return mapRc;
  };

  const tupleMapBoth = (outPtr, firstClosurePtr, secondClosurePtr, tuplePtr) => {
    const elements = tupleElements(tuplePtr);
    if (!elements) {
      writeOut(outPtr, tuplePtr);
      return RC_SUCCESS;
    }

    const firstArg = elements.boxed ? elements.first : newIntHandle(elements.first);
    const secondArg = elements.boxed ? elements.second : newIntHandle(elements.second);
    const firstResult = invokeClosure(firstClosurePtr, [firstArg]);
    if (!elements.boxed) release(firstArg);
    if (firstResult.rc !== RC_SUCCESS) return firstResult.rc;

    const secondResult = invokeClosure(secondClosurePtr, [secondArg]);
    if (!elements.boxed) release(secondArg);
    if (secondResult.rc !== RC_SUCCESS) {
      release(firstResult.value);
      return secondResult.rc;
    }

    if (elements.boxed) {
      return tuple2(outPtr, firstResult.value, secondResult.value);
    }

    const mapRc = tuple2Ints(outPtr, firstResult.value, secondResult.value);
    release(firstResult.value);
    release(secondResult.value);
    return mapRc;
  };

  const internOrder = (value) => {
    const key = value | 0;
    if (!orderHandles.has(key)) {
      orderHandles.set(key, allocHandle({ tag: TAG_ORDER, value: key }));
    }
    return orderHandles.get(key);
  };

  const newOrder = (outPtr, value) => {
    writeOut(outPtr, internOrder(wasmScalarArg(value)));
    return RC_SUCCESS;
  };

  const basicsCompare = (outPtr, leftPtr, rightPtr) => {
    writeOut(outPtr, internOrder(compareValues(leftPtr, rightPtr)));
    return RC_SUCCESS;
  };

  const basicsNot = (outPtr, valuePtr) => newInt(outPtr, intValue(valuePtr) === 0 ? 1 : 0);

  const tuple2Ints = (outPtr, aPtr, bPtr) => {
    writeOut(
      outPtr,
      allocHandle({
        tag: TAG_TUPLE2,
        first: newIntHandle(intValue(aPtr)),
        second: newIntHandle(intValue(bPtr)),
      })
    );
    return RC_SUCCESS;
  };

  const tuple2 = (outPtr, firstPtr, secondPtr) => {
    writeOut(
      outPtr,
      allocHandle({
        tag: TAG_TUPLE2,
        first: storeRecordField(firstPtr),
        second: storeRecordField(secondPtr),
      })
    );
    return RC_SUCCESS;
  };

  const tuplePairItems = (ptr) => {
    const payload = readHandle(ptr);
    if (!payload) return [0, 0];

    if (payload.tag === TAG_TUPLE2) {
      return [intValue(payload.first), intValue(payload.second)];
    }

    if (payload.tag === TAG_LIST) {
      return [payload.items[0] ?? 0, payload.items[1] ?? 0];
    }

    return [0, 0];
  };

  const listItemHandle = (item) => {
    if (item == null) return newIntHandle(0);
    if (handles.has(item | 0)) return item | 0;
    return newIntHandle(item | 0);
  };

  const nestedTupleFromListItems = (items, startIndex) => {
    if (startIndex >= items.length) return newIntHandle(0);
    const first = listItemHandle(items[startIndex]);
    if (startIndex === items.length - 1) return first;
    const second = nestedTupleFromListItems(items, startIndex + 1);
    return allocHandle({ tag: TAG_TUPLE2, first, second });
  };

  const writeTupleProjField = (outPtr, fieldPtr) => {
    const fieldPayload = readHandle(fieldPtr);
    if (fieldPayload?.tag === TAG_STRING) {
      writeOut(outPtr, newStringHandle(fieldPayload.value));
    } else if (fieldPayload?.tag === TAG_CHAR) {
      writeOut(outPtr, newCharHandle(fieldPayload.value));
    } else {
      writeOut(outPtr, fieldPtr);
      if (fieldPtr) retain(null, fieldPtr);
    }
    return RC_SUCCESS;
  };

  const tupleFieldAccess = (outPtr, tuplePtr, index) => {
    const payload = readHandle(tuplePtr);
    if (!payload || payload.tag !== TAG_TUPLE2) {
      writeOut(outPtr, newIntHandle(0));
      return RC_SUCCESS;
    }
    const field = index === 1 ? payload.second : payload.first;
    return writeTupleProjField(outPtr, field);
  };

  const runtimeTupleFirst = (outPtr, tuplePtr) => tupleFieldAccess(outPtr, tuplePtr, 0);
  const runtimeTupleSecond = (outPtr, tuplePtr) => tupleFieldAccess(outPtr, tuplePtr, 1);

  const tupleProj = (outPtr, tuplePtr, indexPtr) => {
    const index = wasmScalarArg(indexPtr);
    let subject = tuplePtr;
    const maybe = readHandle(tuplePtr);
    if (maybe?.tag === TAG_MAYBE && maybe.value != null) {
      subject = maybe.value;
    }

    const payload = readHandle(subject);

    if (payload?.tag === TAG_TUPLE2) {
      const field = index === 1 ? payload.second : payload.first;
      return writeTupleProjField(outPtr, field);
    }

    if (payload?.tag === TAG_RESULT) {
      if (index === 1) {
        if (payload.value != null) {
          writeOut(outPtr, payload.value);
          retain(null, payload.value);
          return RC_SUCCESS;
        }
        writeOut(outPtr, newIntHandle(0));
        return RC_SUCCESS;
      }
      if (index === 0) {
        const tag =
          payload.ctorTag != null ? payload.ctorTag | 0 : payload.isOk ? 1 : 2;
        return newInt(outPtr, tag);
      }
    }

    if (payload?.tag === TAG_BYTES) {
      writeOut(outPtr, subject);
      retain(null, subject);
      return RC_SUCCESS;
    }

    if (payload?.tag === TAG_LIST) {
      const items = payload.items ?? [];
      if (index === 0) {
        const item = listItemHandle(items[0]);
        writeOut(outPtr, item);
        if (handles.has(item)) retain(null, item);
        return RC_SUCCESS;
      }
      if (index === 1) {
        if (items.length <= 1) {
          writeOut(outPtr, newIntHandle(0));
          return RC_SUCCESS;
        }
        const nested = nestedTupleFromListItems(items, 1);
        writeOut(outPtr, nested);
        retain(null, nested);
        return RC_SUCCESS;
      }
    }

    const items = listItems(subject);
    const item = listItemHandle(items[index]);
    writeOut(outPtr, item);
    if (handles.has(item)) retain(null, item);
    return RC_SUCCESS;
  };

  const normalizePushUrl = (url) => {
    if (!url || typeof url !== "string") return url;
    return url.replace(/^(https?:\/\/[^/?#]+)([^/?#].*)$/, (match, origin, rest) => {
      if (!rest || rest.startsWith("/") || rest.startsWith("?") || rest.startsWith("#")) {
        return match;
      }
      return `${origin}/${rest}`;
    });
  };

  const stringValue = (ptr) => {
    if (!ptr) return "";
    const payload = handles.get(ptr);
    if (payload?.tag === TAG_STRING) return payload.value;
    const items = listItems(ptr);
    if (items.length > 0) {
      const parts = items.map((item) => {
        const part = readHandle(item);
        return part?.tag === TAG_STRING ? part.value : "";
      });
      if (parts.some(Boolean)) return parts.join("");
    }
    return "";
  };

  const newStringHandle = (text) => allocHandle({ tag: TAG_STRING, value: String(text) });

  domEventRuntime = createDomEventRuntime({
    allocHandle,
    newStringHandle,
    newIntHandle,
    tuple2,
    TAG_RECORD,
    TAG_TUPLE2,
    TAG_STRING,
    TAG_INT,
    TAG_MAYBE,
  });

  urlRuntimeApi = createUrlRuntime({
    allocHandle,
    newStringHandle,
    newIntHandle,
    stringValue,
    TAG_RECORD,
    TAG_MAYBE,
    TAG_TUPLE2,
    TAG_INT,
    constructorTags,
  });

  routeBytesRuntime = createRouteBytesRuntime();
  routeBytesRuntime.setRuntimeFetcher(routeBytesRuntime.defaultRuntimeFetcher);

  vdomPatchRuntime = createVdomPatchRuntime({
    readHandle,
    resolveHtml,
    stringValue,
    listItems,
    retain,
    release,
    TAG_VDOM,
    TAG_RECORD,
    TAG_TUPLE2,
    TAG_INT,
    attachDomEvent,
    forceLazyHtml,
  });

  cloneHandleForProgram = (handlePtr) => {
    const ptr = handlePtr | 0;
    if (!ptr || !handles.has(ptr)) {
      return ptr;
    }

    const payload = readHandle(ptr);

    switch (payload.tag) {
      case TAG_CLOSURE:
        return allocHandle({
          tag: TAG_CLOSURE,
          fnIndex: payload.fnIndex | 0,
          arity: payload.arity | 0,
          captures: (payload.captures ?? []).map((capture) => cloneHandleForProgram(capture | 0)),
          applied: (payload.applied ?? []).map((arg) => cloneHandleForProgram(arg | 0)),
        });
      case TAG_RECORD:
        return allocHandle({
          tag: TAG_RECORD,
          fields: (payload.fields ?? []).map((field) => cloneHandleForProgram(field | 0)),
        });
      case TAG_LIST:
        return allocHandle({
          tag: TAG_LIST,
          items: (payload.items ?? []).map((item) => cloneHandleForProgram(item | 0)),
        });
      case TAG_TUPLE2:
        return allocHandle({
          tag: TAG_TUPLE2,
          first: cloneHandleForProgram(payload.first | 0),
          second: cloneHandleForProgram(payload.second | 0),
        });
      case TAG_MAYBE:
        return allocHandle({
          tag: TAG_MAYBE,
          value: payload.value ? cloneHandleForProgram(payload.value | 0) : null,
          ...(payload.ctorTag != null ? { ctorTag: payload.ctorTag | 0 } : {}),
          ...(payload.isJust != null ? { isJust: payload.isJust } : {}),
        });
      case TAG_RESULT:
        return allocHandle({
          tag: TAG_RESULT,
          isOk: payload.isOk,
          ...(payload.ctorTag != null ? { ctorTag: payload.ctorTag | 0 } : {}),
          value: payload.value ? cloneHandleForProgram(payload.value | 0) : null,
        });
      case TAG_INT:
        return newIntHandle(payload.value | 0);
      case TAG_STRING:
        return newStringHandle(payload.value);
      case TAG_FLOAT:
        return allocHandle({ tag: TAG_FLOAT, value: payload.value });
      case TAG_CHAR:
        return allocHandle({ tag: TAG_CHAR, value: payload.value });
      case TAG_ORDER:
        return allocHandle({ tag: TAG_ORDER, value: payload.value });
      default:
        return allocHandle({ ...payload });
    }
  };

  const cloneRecordHandle = (recordPtr) => {
    const cloned = cloneHandleForProgram(recordPtr | 0);
    const payload = readHandle(cloned);
    return payload?.tag === TAG_RECORD ? cloned : recordPtr | 0;
  };

  const resultPayload = (ptr) => {
    const payload = readHandle(ptr);
    return payload?.tag === TAG_RESULT ? payload : null;
  };

  const resultOkOwn = (outPtr, valueHandle, tagPtr) => {
    const ctorTag = tagPtr != null && tagPtr !== 0 ? wasmScalarArg(tagPtr) : 1;
    writeOut(
      outPtr,
      allocHandle({ tag: TAG_RESULT, isOk: true, ctorTag, value: valueHandle })
    );
    return RC_SUCCESS;
  };

  const resultErrOwn = (outPtr, valueHandle, tagPtr) => {
    const ctorTag = tagPtr != null && tagPtr !== 0 ? wasmScalarArg(tagPtr) : 2;
    writeOut(
      outPtr,
      allocHandle({ tag: TAG_RESULT, isOk: false, ctorTag, value: valueHandle })
    );
    return RC_SUCCESS;
  };

  const resultWithDefault = (outPtr, defaultPtr, resultPtr) => {
    const result = resultPayload(resultPtr);
    if (result?.isOk && result.value != null) {
      return newInt(outPtr, intValue(asHandle(result.value)));
    }

    return newInt(outPtr, wasmScalarArg(defaultPtr));
  };

  const resultMap = (outPtr, closurePtr, resultPtr) => {
    const result = resultPayload(resultPtr);
    if (!result) {
      return resultErrOwn(outPtr, newStringHandle("invalid"));
    }

    if (!result.isOk) {
      writeOut(outPtr, resultPtr);
      return RC_SUCCESS;
    }

    const { rc, value } = invokeClosure(closurePtr, [asHandle(result.value)]);
    if (rc !== RC_SUCCESS) return rc;
    return resultOkOwn(outPtr, value);
  };

  const resultMapError = (outPtr, closurePtr, resultPtr) => {
    const result = resultPayload(resultPtr);
    if (!result) {
      writeOut(outPtr, resultPtr);
      return RC_SUCCESS;
    }

    if (result.isOk) {
      writeOut(outPtr, resultPtr);
      return RC_SUCCESS;
    }

    const { rc, value } = invokeClosure(closurePtr, [asHandle(result.value)]);
    if (rc !== RC_SUCCESS) return rc;
    return resultErrOwn(outPtr, value);
  };

  const resultAndThen = (outPtr, closurePtr, resultPtr) => {
    const result = resultPayload(resultPtr);
    if (!result) {
      return resultErrOwn(outPtr, newStringHandle("invalid"));
    }

    if (!result.isOk) {
      writeOut(outPtr, resultPtr);
      return RC_SUCCESS;
    }

    const { rc, value } = invokeClosure(closurePtr, [asHandle(result.value)]);
    if (rc !== RC_SUCCESS) return rc;
    writeOut(outPtr, asHandle(value));
    return RC_SUCCESS;
  };

  const resultToMaybe = (outPtr, resultPtr) => {
    const result = resultPayload(resultPtr);
    if (!result || !result.isOk || result.value == null) {
      return maybeNothing(outPtr);
    }

    return maybeJustOwn(outPtr, result.value);
  };

  const resultFromMaybe = (outPtr, errPtr, maybePtr) => {
    const maybe = readHandle(maybePtr);
    if (maybe?.tag === TAG_MAYBE && maybe.value != null) {
      return resultOkOwn(outPtr, asHandle(maybe.value));
    }

    return resultErrOwn(outPtr, asHandle(errPtr));
  };

  const stringAppend = (outPtr, leftPtr, rightPtr) => {
    writeOut(outPtr, newStringHandle(stringValue(leftPtr) + stringValue(rightPtr)));
    return RC_SUCCESS;
  };

  const codePoints = (str) => [...str];

  const fromCodePoints = (cps) => cps.join("");

  const charCode = (ptr) => {
    const payload = handles.get(ptr);
    if (payload?.tag === TAG_CHAR) return payload.value | 0;
    return intValue(ptr);
  };

  const newCharHandle = (code) => allocHandle({ tag: TAG_CHAR, value: code | 0 });

  const newChar = (outPtr, code) => {
    writeOut(outPtr, newCharHandle(wasmScalarArg(code)));
    return RC_SUCCESS;
  };

  const isStringHandle = (ptr) => readHandle(ptr)?.tag === TAG_STRING;

  const stringLen = (str) => codePoints(str).length;

  const writeString = (outPtr, text) => {
    writeOut(outPtr, newStringHandle(text));
    return RC_SUCCESS;
  };

  const append = (outPtr, leftPtr, rightPtr) => {
    if (isStringHandle(leftPtr) || isStringHandle(rightPtr)) {
      return stringAppend(outPtr, leftPtr, rightPtr);
    }
    return listAppend(outPtr, leftPtr, rightPtr);
  };

  const stringLengthBoxed = (outPtr, strPtr) => newInt(outPtr, stringLen(stringValue(strPtr)));
  // Plan/WASM lower String.length as runtime.string_length_val (RC out-ptr ABI).
  const stringLengthVal = stringLengthBoxed;

  const stringIsEmpty = (outPtr, strPtr) => newInt(outPtr, stringValue(strPtr).length === 0 ? 1 : 0);

  const stringReverse = (outPtr, strPtr) => {
    const cps = codePoints(stringValue(strPtr));
    return writeString(outPtr, fromCodePoints(cps.reverse()));
  };

  const stringRepeat = (outPtr, countPtr, strPtr) => {
    const count = Math.max(0, intValue(countPtr));
    return writeString(outPtr, stringValue(strPtr).repeat(count));
  };

  const stringReplace = (outPtr, oldPtr, newPtr, strPtr) => {
    const haystack = stringValue(strPtr);
    const needle = stringValue(oldPtr);
    const replacement = stringValue(newPtr);
    if (!needle) return writeString(outPtr, haystack);
    return writeString(outPtr, haystack.split(needle).join(replacement));
  };

  const stringFromIntValue = (outPtr, nPtr) => writeString(outPtr, String(wasmScalarArg(nPtr)));

  const parseStringInt = (str) => {
    if (!str || !/^[-+]?\d+$/.test(str)) return null;
    const value = Number(str);
    return Number.isSafeInteger(value) ? value : null;
  };

  const stringToInt = (outPtr, strPtr) => {
    const parsed = parseStringInt(stringValue(strPtr));
    if (parsed == null) return maybeNothing(outPtr);
    return maybeJustOwn(outPtr, newIntHandle(parsed));
  };

  const floatFromHandle = (ptr) => floatNumber(ptr);

  const formatStringFromFloat = (value) => {
    const whole = Math.trunc(value);
    if (value === whole) return String(whole);
    const abs = Math.abs(value);
    const absWhole = Math.trunc(abs);
    let frac3 = Math.round((abs - absWhole) * 1000);
    if (frac3 >= 1000) {
      return String(value < 0 ? whole - 1 : whole + 1);
    }
    let text = `${value < 0 ? "-" : ""}${absWhole}.${String(frac3).padStart(3, "0")}`;
    text = text.replace(/\.?0+$/, "");
    return text;
  };

  const stringFromFloat = (outPtr, floatPtr) =>
    writeString(outPtr, formatStringFromFloat(floatFromHandle(floatPtr)));

  const parseStringFloat = (str) => {
    if (!str || !/^[-+]?(?:\d+\.?\d*|\.\d+)$/.test(str)) return null;
    const value = Number(str);
    return Number.isFinite(value) ? value : null;
  };

  const stringToFloat = (outPtr, strPtr) => {
    const parsed = parseStringFloat(stringValue(strPtr));
    if (parsed == null) return maybeNothing(outPtr);
    return maybeJustOwn(outPtr, allocHandle({ tag: TAG_FLOAT, value: parsed }));
  };

  const mapAsciiCase = (str, upper) => {
    return str.replace(/[a-zA-Z]/g, (ch) => {
      const code = ch.charCodeAt(0);
      if (upper) return code >= 97 && code <= 122 ? String.fromCharCode(code - 32) : ch;
      return code >= 65 && code <= 90 ? String.fromCharCode(code + 32) : ch;
    });
  };

  const stringToUpper = (outPtr, strPtr) =>
    writeString(outPtr, mapAsciiCase(stringValue(strPtr), true));

  const stringToLower = (outPtr, strPtr) =>
    writeString(outPtr, mapAsciiCase(stringValue(strPtr), false));

  const trimEdge = (str, left, right) => {
    let start = 0;
    let end = str.length;
    const ws = /[ \t\n\r]/;
    if (left) while (start < end && ws.test(str[start])) start += 1;
    if (right) while (end > start && ws.test(str[end - 1])) end -= 1;
    return str.slice(start, end);
  };

  const stringTrim = (outPtr, strPtr) => writeString(outPtr, trimEdge(stringValue(strPtr), true, true));
  const stringTrimLeft = (outPtr, strPtr) => writeString(outPtr, trimEdge(stringValue(strPtr), true, false));
  const stringTrimRight = (outPtr, strPtr) => writeString(outPtr, trimEdge(stringValue(strPtr), false, true));

  const stringContains = (outPtr, subPtr, strPtr) =>
    newInt(outPtr, stringValue(strPtr).includes(stringValue(subPtr)) ? 1 : 0);

  const stringStartsWith = (outPtr, prefixPtr, strPtr) =>
    newInt(outPtr, stringValue(strPtr).startsWith(stringValue(prefixPtr)) ? 1 : 0);

  const stringEndsWith = (outPtr, suffixPtr, strPtr) =>
    newInt(outPtr, stringValue(strPtr).endsWith(stringValue(suffixPtr)) ? 1 : 0);

  const stringEquals = (outPtr, leftPtr, rightPtr) =>
    newInt(outPtr, stringValue(leftPtr) === stringValue(rightPtr) ? 1 : 0);

  const stringEqualsLiteral = (outPtr, strPtr, literalId) => {
    const literal = lookupImmortalString(literalId);
    return newInt(outPtr, stringValue(strPtr) === literal ? 1 : 0);
  };

  const stringSplit = (outPtr, sepPtr, strPtr) => {
    const sep = stringValue(sepPtr);
    const parts = sep ? stringValue(strPtr).split(sep) : [...stringValue(strPtr)];
    return writeList(outPtr, parts.map((part) => newStringHandle(part)));
  };

  const stringJoin = (outPtr, sepPtr, listPtr) => {
    const sep = stringValue(sepPtr);
    const parts = listItems(listPtr).map((item) => stringValue(asHandle(item)));
    return writeString(outPtr, parts.join(sep));
  };

  const stringWords = (outPtr, strPtr) => {
    const space = newStringHandle(" ");
    const rc = stringSplit(outPtr, space, strPtr);
    release(space);
    return rc;
  };

  const stringLines = (outPtr, strPtr) => {
    const nl = newStringHandle("\n");
    const rc = stringSplit(outPtr, nl, strPtr);
    release(nl);
    return rc;
  };

  const sliceCodePoints = (outPtr, startRaw, endRaw, strPtr) => {
    const cps = codePoints(stringValue(strPtr));
    let start = startRaw | 0;
    let end = endRaw | 0;
    if (start < 0) start = cps.length + start;
    if (end < 0) end = cps.length + end;
    start = Math.max(0, Math.min(start, cps.length));
    end = Math.max(0, Math.min(end, cps.length));
    if (end <= start) return writeString(outPtr, "");
    return writeString(outPtr, fromCodePoints(cps.slice(start, end)));
  };

  const stringSlice = (outPtr, startPtr, endPtr, strPtr) =>
    sliceCodePoints(outPtr, wasmScalarArg(startPtr), wasmScalarArg(endPtr), strPtr);

  const stringLeft = (outPtr, countPtr, strPtr) =>
    sliceCodePoints(outPtr, 0, wasmScalarArg(countPtr), strPtr);

  const stringRight = (outPtr, countPtr, strPtr) => {
    const len = stringLen(stringValue(strPtr));
    const count = wasmScalarArg(countPtr);
    return sliceCodePoints(outPtr, Math.max(0, len - count), len, strPtr);
  };

  const stringDropLeft = (outPtr, countPtr, strPtr) => {
    const len = stringLen(stringValue(strPtr));
    return sliceCodePoints(outPtr, wasmScalarArg(countPtr), len, strPtr);
  };

  const stringDropRight = (outPtr, countPtr, strPtr) => {
    const len = stringLen(stringValue(strPtr));
    const count = wasmScalarArg(countPtr);
    return sliceCodePoints(outPtr, 0, Math.max(0, len - count), strPtr);
  };

  const stringCons = (outPtr, chPtr, strPtr) => {
    const prefix = String.fromCodePoint(charCode(chPtr));
    return writeString(outPtr, prefix + stringValue(strPtr));
  };

  const stringUncons = (outPtr, strPtr) => {
    const cps = codePoints(stringValue(strPtr));
    if (cps.length === 0) return maybeNothing(outPtr);
    const ch = newCharHandle(cps[0].codePointAt(0));
    const rest = newStringHandle(fromCodePoints(cps.slice(1)));
    const pair = allocHandle({ tag: TAG_TUPLE2, first: ch, second: rest });
    return maybeJustOwn(outPtr, pair);
  };

  const stringToList = (outPtr, strPtr) => {
    const items = codePoints(stringValue(strPtr)).map((ch) => newCharHandle(ch.codePointAt(0)));
    writeOut(outPtr, allocHandle({ tag: TAG_LIST, items }));
    return RC_SUCCESS;
  };

  const stringFromList = (outPtr, listPtr) => {
    const chars = listItems(listPtr).map((item) => String.fromCodePoint(charCode(asHandle(item))));
    return writeString(outPtr, chars.join(""));
  };

  const stringFromChar = (outPtr, chPtr) =>
    writeString(outPtr, String.fromCodePoint(charCode(chPtr)));

  const padString = (text, target, padChar, left) => {
    const cur = stringLen(text);
    if (cur >= target) return text;
    const padCount = target - cur;
    const fill = String.fromCodePoint(padChar).repeat(padCount);
    return left ? fill + text : text + fill;
  };

  const stringPadLeft = (outPtr, targetPtr, chPtr, strPtr) => {
    const text = stringValue(strPtr);
    const target = intValue(targetPtr);
    const padChar = charCode(chPtr);
    return writeString(outPtr, padString(text, target, padChar, true));
  };

  const stringPadRight = (outPtr, targetPtr, chPtr, strPtr) => {
    const text = stringValue(strPtr);
    const target = intValue(targetPtr);
    const padChar = charCode(chPtr);
    return writeString(outPtr, padString(text, target, padChar, false));
  };

  const stringPad = (outPtr, targetPtr, chPtr, strPtr) =>
    stringPadLeft(outPtr, targetPtr, chPtr, strPtr);

  const stringMap = (outPtr, closurePtr, strPtr) => {
    const mapped = [];
    for (const ch of codePoints(stringValue(strPtr))) {
      const arg = newCharHandle(ch.codePointAt(0));
      const { rc, value } = invokeClosure(closurePtr, [arg]);
      release(arg);
      if (rc !== RC_SUCCESS) return rc;
      mapped.push(String.fromCodePoint(charCode(value)));
      release(value);
    }
    return writeString(outPtr, mapped.join(""));
  };

  const stringFilter = (outPtr, closurePtr, strPtr) => {
    const kept = [];
    for (const ch of codePoints(stringValue(strPtr))) {
      const arg = newCharHandle(ch.codePointAt(0));
      const { rc, value } = invokeClosure(closurePtr, [arg]);
      release(arg);
      if (rc !== RC_SUCCESS) return rc;
      if (intValue(value) !== 0) kept.push(ch);
      release(value);
    }
    return writeString(outPtr, kept.join(""));
  };

  const stringFoldl = (outPtr, closurePtr, accPtr, strPtr) => {
    let accHandle = asHandle(accPtr);
    for (const ch of codePoints(stringValue(strPtr))) {
      const arg = newCharHandle(ch.codePointAt(0));
      const { rc, value } = invokeClosure(closurePtr, [arg, accHandle]);
      if (rc !== RC_SUCCESS) return rc;
      if (accHandle) release(accHandle);
      accHandle = value;
    }
    writeOut(outPtr, accHandle);
    return RC_SUCCESS;
  };

  const stringFoldr = (outPtr, closurePtr, accPtr, strPtr) => {
    let accHandle = asHandle(accPtr);
    const cps = codePoints(stringValue(strPtr));
    for (let i = cps.length - 1; i >= 0; i--) {
      const arg = newCharHandle(cps[i].codePointAt(0));
      const { rc, value } = invokeClosure(closurePtr, [arg, accHandle]);
      if (rc !== RC_SUCCESS) return rc;
      if (accHandle) release(accHandle);
      accHandle = value;
    }
    writeOut(outPtr, accHandle);
    return RC_SUCCESS;
  };

  const stringAny = (outPtr, closurePtr, strPtr) => {
    for (const ch of codePoints(stringValue(strPtr))) {
      const arg = newCharHandle(ch.codePointAt(0));
      const { rc, value } = invokeClosure(closurePtr, [arg]);
      release(arg);
      if (rc !== RC_SUCCESS) return rc;
      const truthy = intValue(value) !== 0;
      release(value);
      if (truthy) return newInt(outPtr, 1);
    }
    return newInt(outPtr, 0);
  };

  const stringAll = (outPtr, closurePtr, strPtr) => {
    const cps = codePoints(stringValue(strPtr));
    if (cps.length === 0) return newInt(outPtr, 0);
    for (const ch of cps) {
      const arg = newCharHandle(ch.codePointAt(0));
      const { rc, value } = invokeClosure(closurePtr, [arg]);
      release(arg);
      if (rc !== RC_SUCCESS) return rc;
      const truthy = intValue(value) !== 0;
      release(value);
      if (!truthy) return newInt(outPtr, 0);
    }
    return newInt(outPtr, 1);
  };

  const stringIndexes = (outPtr, subPtr, strPtr) => {
    const haystack = stringValue(strPtr);
    const needle = stringValue(subPtr);
    const items = [];
    if (needle) {
      let index = haystack.indexOf(needle);
      while (index !== -1) {
        items.push(index);
        index = haystack.indexOf(needle, index + 1);
      }
    }
    return writeList(outPtr, items);
  };

  const charToCode = (outPtr, chPtr) => newInt(outPtr, charCode(chPtr));

  const charToUpper = (outPtr, chPtr) => {
    let code = charCode(chPtr);
    if (code >= 97 && code <= 122) code -= 32;
    return newChar(outPtr, code);
  };

  const charIsAlpha = (outPtr, chPtr) => {
    const code = charCode(chPtr);
    const alpha =
      (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
    return newInt(outPtr, alpha ? 1 : 0);
  };

  const charIsDigit = (outPtr, chPtr) => {
    const code = charCode(chPtr);
    return newInt(outPtr, code >= 48 && code <= 57 ? 1 : 0);
  };

  const charFromCode = (outPtr, codePtr) => newChar(outPtr, wasmScalarArg(codePtr));

  const charToLower = (outPtr, chPtr) => {
    let code = charCode(chPtr);
    if (code >= 65 && code <= 90) code += 32;
    return newChar(outPtr, code);
  };

  const charIsUpper = (outPtr, chPtr) => {
    const code = charCode(chPtr);
    return newInt(outPtr, code >= 65 && code <= 90 ? 1 : 0);
  };

  const charIsLower = (outPtr, chPtr) => {
    const code = charCode(chPtr);
    return newInt(outPtr, code >= 97 && code <= 122 ? 1 : 0);
  };

  const charIsAlphaNum = (outPtr, chPtr) => {
    const code = charCode(chPtr);
    const ok =
      (code >= 48 && code <= 57) ||
      (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122);
    return newInt(outPtr, ok ? 1 : 0);
  };

  const charIsOctDigit = (outPtr, chPtr) => {
    const code = charCode(chPtr);
    return newInt(outPtr, code >= 48 && code <= 55 ? 1 : 0);
  };

  const charIsHexDigit = (outPtr, chPtr) => {
    const code = charCode(chPtr);
    const ok =
      (code >= 48 && code <= 57) ||
      (code >= 65 && code <= 70) ||
      (code >= 97 && code <= 102);
    return newInt(outPtr, ok ? 1 : 0);
  };

  const bitwiseAnd = (outPtr, aPtr, bPtr) => newInt(outPtr, wasmScalarArg(aPtr) & wasmScalarArg(bPtr));
  const bitwiseOr = (outPtr, aPtr, bPtr) => newInt(outPtr, wasmScalarArg(aPtr) | wasmScalarArg(bPtr));
  const bitwiseXor = (outPtr, aPtr, bPtr) => newInt(outPtr, wasmScalarArg(aPtr) ^ wasmScalarArg(bPtr));
  const bitwiseComplement = (outPtr, aPtr) => newInt(outPtr, ~wasmScalarArg(aPtr));
  const bitwiseShiftLeftBy = (outPtr, bitsPtr, valuePtr) =>
    newInt(outPtr, wasmScalarArg(valuePtr) << (wasmScalarArg(bitsPtr) & 31));
  const bitwiseShiftRightBy = (outPtr, bitsPtr, valuePtr) =>
    newInt(outPtr, wasmScalarArg(valuePtr) >> (wasmScalarArg(bitsPtr) & 31));
  const bitwiseShiftRightZfBy = (outPtr, bitsPtr, valuePtr) =>
    newInt(outPtr, wasmScalarArg(valuePtr) >>> (wasmScalarArg(bitsPtr) & 31));

  const debugToString = (outPtr, valuePtr) => {
    const payload = readHandle(valuePtr);
    let text = "0";
    if (payload?.tag === TAG_INT) text = String(payload.value);
    else if (payload?.tag === TAG_FLOAT) text = String(payload.value);
    else if (payload?.tag === TAG_STRING) text = payload.value;
    else if (payload?.tag === TAG_CHAR) text = String.fromCodePoint(payload.value);
    else text = String(wasmScalarArg(valuePtr));
    return writeString(outPtr, text);
  };

  const debugLog = (outPtr, _labelPtr, valuePtr) => {
    if (handles.has(valuePtr)) {
      writeOut(outPtr, valuePtr);
    } else {
      writeOut(outPtr, newIntHandle(wasmScalarArg(valuePtr)));
    }
    return RC_SUCCESS;
  };

  const debugTodo = (outPtr, _labelPtr) => newInt(outPtr, 0);

  const floatNumber = (ptr) => {
    const payload = readHandle(ptr);
    if (payload?.tag === TAG_FLOAT) return payload.value;
    if (payload?.tag === TAG_INT) return payload.value;
    return wasmScalarArg(ptr);
  };

  const writeFloatNumber = (outPtr, value) => {
    const buf = new ArrayBuffer(4);
    const view = new DataView(buf);
    view.setFloat32(0, value, true);
    return newFloat(outPtr, view.getUint32(0, true) | 0);
  };

  const basicsToFloat = (outPtr, nPtr) => writeFloatNumber(outPtr, floatNumber(nPtr));
  const basicsTruncate = (outPtr, nPtr) => newInt(outPtr, Math.trunc(floatNumber(nPtr)));
  const basicsRound = (outPtr, nPtr) => newInt(outPtr, Math.round(floatNumber(nPtr)));
  const basicsFloor = (outPtr, nPtr) => newInt(outPtr, Math.floor(floatNumber(nPtr)));
  const basicsCeiling = (outPtr, nPtr) => newInt(outPtr, Math.ceil(floatNumber(nPtr)));
  const basicsSqrt = (outPtr, nPtr) => writeFloatNumber(outPtr, Math.sqrt(floatNumber(nPtr)));
  const basicsSin = (outPtr, nPtr) => writeFloatNumber(outPtr, Math.sin(floatNumber(nPtr)));
  const basicsCos = (outPtr, nPtr) => writeFloatNumber(outPtr, Math.cos(floatNumber(nPtr)));
  const basicsTan = (outPtr, nPtr) => writeFloatNumber(outPtr, Math.tan(floatNumber(nPtr)));
  const basicsAsin = (outPtr, nPtr) => writeFloatNumber(outPtr, Math.asin(floatNumber(nPtr)));
  const basicsAcos = (outPtr, nPtr) => writeFloatNumber(outPtr, Math.acos(floatNumber(nPtr)));
  const basicsAtan = (outPtr, nPtr) => writeFloatNumber(outPtr, Math.atan(floatNumber(nPtr)));
  const basicsAtan2 = (outPtr, yPtr, xPtr) =>
    writeFloatNumber(outPtr, Math.atan2(floatNumber(yPtr), floatNumber(xPtr)));
  const basicsDegrees = (outPtr, nPtr) =>
    writeFloatNumber(outPtr, (floatNumber(nPtr) * 180) / Math.PI);
  const basicsRadians = (outPtr, nPtr) =>
    writeFloatNumber(outPtr, (floatNumber(nPtr) * Math.PI) / 180);
  const basicsTurns = (outPtr, nPtr) =>
    writeFloatNumber(outPtr, floatNumber(nPtr) * 2 * Math.PI);
  const basicsLogBase = (outPtr, basePtr, nPtr) =>
    writeFloatNumber(outPtr, Math.log(floatNumber(nPtr)) / Math.log(floatNumber(basePtr)));
  const basicsIsNan = (outPtr, nPtr) => newInt(outPtr, Number.isNaN(floatNumber(nPtr)) ? 1 : 0);
  const basicsIsInfinite = (outPtr, nPtr) =>
    newInt(outPtr, !Number.isFinite(floatNumber(nPtr)) && !Number.isNaN(floatNumber(nPtr)) ? 1 : 0);
  const basicsFromPolar = (outPtr, rPtr, thetaPtr) => {
    const r = floatNumber(rPtr);
    const theta = floatNumber(thetaPtr);
    return tuple2(
      outPtr,
      newIntHandle(Math.trunc(r * Math.cos(theta))),
      newIntHandle(Math.trunc(r * Math.sin(theta)))
    );
  };
  const basicsToPolar = (outPtr, xPtr, yPtr) => {
    const x = floatNumber(xPtr);
    const y = floatNumber(yPtr);
    return tuple2Ints(
      outPtr,
      newIntHandle(Math.trunc(Math.sqrt(x * x + y * y))),
      newIntHandle(Math.trunc(Math.atan2(y, x)))
    );
  };
  const basicsMax = (outPtr, aPtr, bPtr) =>
    retain(outPtr, compareValues(aPtr, bPtr) >= 0 ? aPtr : bPtr);
  const basicsMin = (outPtr, aPtr, bPtr) =>
    retain(outPtr, compareValues(aPtr, bPtr) <= 0 ? aPtr : bPtr);
  const basicsClamp = (outPtr, lowPtr, highPtr, nPtr) => {
    const below = compareValues(nPtr, lowPtr);
    if (below < 0) return retain(outPtr, lowPtr);
    const above = compareValues(nPtr, highPtr);
    if (above > 0) return retain(outPtr, highPtr);
    return retain(outPtr, nPtr);
  };
  const basicsModBy = (outPtr, modPtr, nPtr) => {
    const mod = wasmScalarArg(modPtr);
    const n = wasmScalarArg(nPtr);
    const out = ((n % mod) + mod) % mod;
    return newInt(outPtr, out);
  };
  const basicsRemainderBy = (outPtr, modPtr, nPtr) =>
    newInt(outPtr, wasmScalarArg(nPtr) % wasmScalarArg(modPtr));
  const basicsNegate = (outPtr, nPtr) => newInt(outPtr, -wasmScalarArg(nPtr));
  const basicsAbs = (outPtr, nPtr) => newInt(outPtr, Math.abs(wasmScalarArg(nPtr)));
  const basicsXor = (outPtr, aPtr, bPtr) =>
    newInt(outPtr, (intValue(aPtr) !== 0) !== (intValue(bPtr) !== 0) ? 1 : 0);

  const writeTaggedResult = (outPtr, isOk, valueHandle) => {
    const tagHandle = isOk ? 1 : 0;
    handles.set(tagHandle, { tag: TAG_RESULT, isOk, value: valueHandle });
    if (nextHandle <= tagHandle) nextHandle = tagHandle + 1;
    writeOut(outPtr, tagHandle);
    return RC_SUCCESS;
  };

  const taskSucceed = (outPtr, valuePtr) => {
    const value = handles.has(valuePtr) ? valuePtr : newIntHandle(wasmScalarArg(valuePtr));
    return writeTaggedResult(outPtr, true, value);
  };

  const taskFail = (outPtr, valuePtr) => {
    const value = handles.has(valuePtr) ? valuePtr : newIntHandle(wasmScalarArg(valuePtr));
    return writeTaggedResult(outPtr, false, value);
  };

  const processSpawn = (outPtr, _taskPtr) => writeTaggedResult(outPtr, true, newIntHandle(1));
  const processSleep = (outPtr, _msPtr) => writeTaggedResult(outPtr, true, newIntHandle(0));
  const processKill = (outPtr, _pidPtr) => writeTaggedResult(outPtr, true, newIntHandle(0));

  const normalizeFieldHandle = (ptr) => {
    const p = ptr | 0;
    if (!handles.has(p)) {
      return newIntHandle(wasmScalarArg(p));
    }
    const payload = readHandle(p);
    // WASM tuple2 often passes constructor tags as raw i32.const N. Those collide
    // with early immortal handles (UNIT is handle 1 = Int 0), which would make
    // union_tag_as_int read tag 0 instead of N.
    if (
      payload?.tag === TAG_INT &&
      payload.immortal &&
      p <= 255 &&
      (payload.value | 0) !== p
    ) {
      return newIntHandle(p);
    }
    return p;
  };

  const storeRecordField = (ptr) => {
    const field = normalizeFieldHandle(ptr);
    if (handles.has(field | 0)) {
      retain(null, field);
    }
    return field;
  };

  const recordFieldsFromWasmArgs = (fieldPtrs, storeField) => {
    let end = fieldPtrs.length;
    while (end > 0 && (fieldPtrs[end - 1] | 0) === 0) {
      end -= 1;
    }

    const fields = [];
    for (let i = 0; i < end; i += 1) {
      const ptr = fieldPtrs[i] | 0;
      if (ptr !== 0) {
        fields[i] = storeField(ptr);
      }
    }
    return fields;
  };

  const recordNewValuesInts = (outPtr, ...fieldPtrs) => {
    const fields = recordFieldsFromWasmArgs(fieldPtrs, (ptr) =>
      newIntHandle(wasmScalarArg(ptr))
    );
    writeOut(outPtr, allocHandle({ tag: TAG_RECORD, fields }));
    return RC_SUCCESS;
  };

  const recordNew = (outPtr, ...fieldPtrs) => {
    const fields = recordFieldsFromWasmArgs(fieldPtrs, storeRecordField);
    writeOut(outPtr, allocHandle({ tag: TAG_RECORD, fields }));
    return RC_SUCCESS;
  };

  const recordGet = (outPtr, recordPtr, indexPtr) => {
    const index = wasmScalarArg(indexPtr);
    const fields = readHandle(recordPtr)?.fields ?? [];
    const field = fields[index];
    if (field == null) {
      writeOut(outPtr, newIntHandle(0));
    } else {
      writeOut(outPtr, field);
      if (handles.has(field | 0)) retain(null, field);
    }
    return RC_SUCCESS;
  };

  // Match C elmc_record_update_index_cow_drop: clone+retain fields, then release
  // the old record when a fresh handle is published so caller can null owned[base].
  const recordUpdate = (outPtr, recordPtr, valuePtr, indexPtr) => {
    const index = wasmScalarArg(indexPtr);
    const fields = (readHandle(recordPtr)?.fields ?? []).map(storeRecordField);
    if (index >= 0 && index < fields.length) {
      fields[index] = storeRecordField(valuePtr);
    }
    const next = allocHandle({ tag: TAG_RECORD, fields });
    writeOut(outPtr, next);
    if ((next | 0) !== (recordPtr | 0)) {
      release(recordPtr);
    }
    return RC_SUCCESS;
  };

  const listNthMaybe = (outPtr, listPtr, indexPtr) => {
    const index = wasmScalarArg(indexPtr);
    const items = listItems(listPtr);
    if (index < 0 || index >= items.length) return maybeNothing(outPtr);
    return maybeJust(outPtr, asHandle(items[index]));
  };

  const listNthIntDefault = (outPtr, listPtr, indexPtr, defaultPtr) => {
    const index = wasmScalarArg(indexPtr);
    const items = listItems(listPtr);
    const value = index >= 0 && index < items.length ? intValue(items[index]) : wasmScalarArg(defaultPtr);
    return newInt(outPtr, value);
  };

  const listReplaceNthInt = (outPtr, listPtr, indexPtr, valuePtr) => {
    const index = wasmScalarArg(indexPtr);
    const value = wasmScalarArg(valuePtr);
    const items = [...listItems(listPtr)];
    if (index >= 0 && index < items.length) {
      items[index] = newIntHandle(value);
    }
    return writeList(outPtr, items);
  };

  const listSliceInt = (outPtr, dropPtr, takePtr, listPtr) => {
    const drop = wasmScalarArg(dropPtr);
    const take = wasmScalarArg(takePtr);
    const items = listItems(listPtr).slice(drop, drop + take);
    return writeList(outPtr, items);
  };

  const intListHeadInt = (outPtr, listPtr) => {
    const items = listItems(listPtr);
    return newInt(outPtr, items.length === 0 ? 0 : intValue(items[0]));
  };

  const intListTail = (outPtr, listPtr) => {
    const items = listItems(listPtr);
    return writeList(outPtr, items.slice(1));
  };

  const valuesEqualDeep = (leftPtr, rightPtr, seen) => {
    if (leftPtr === rightPtr) return true;
    const pairKey = `${leftPtr}|${rightPtr}`;
    if (seen.has(pairKey)) return true;
    seen.add(pairKey);

    const left = readHandle(leftPtr);
    const right = readHandle(rightPtr);
    if (!left || !right) return !left && !right;
    if (left.tag !== right.tag) return false;

    switch (left.tag) {
      case TAG_INT:
        return (left.value | 0) === (right.value | 0);
      case TAG_FLOAT:
        return left.value === right.value;
      case TAG_CHAR:
        return left.value === right.value;
      case TAG_STRING:
        return left.value === right.value;
      case TAG_ORDER:
        return (left.value | 0) === (right.value | 0);
      case TAG_TUPLE2:
        return (
          valuesEqualDeep(left.first | 0, right.first | 0, seen) &&
          valuesEqualDeep(left.second | 0, right.second | 0, seen)
        );
      case TAG_LIST: {
        const leftItems = listItems(leftPtr);
        const rightItems = listItems(rightPtr);
        if (leftItems.length !== rightItems.length) return false;
        for (let i = 0; i < leftItems.length; i++) {
          if (!valuesEqualDeep(leftItems[i], rightItems[i], seen)) return false;
        }
        return true;
      }
      case TAG_MAYBE:
        if ((left.value == null) !== (right.value == null)) return false;
        return left.value == null || valuesEqualDeep(left.value | 0, right.value | 0, seen);
      case TAG_RESULT:
        if (left.isOk !== right.isOk) return false;
        return valuesEqualDeep(left.value | 0, right.value | 0, seen);
      case TAG_RECORD: {
        const lf = left.fields ?? [];
        const rf = right.fields ?? [];
        if (lf.length !== rf.length) return false;
        for (let i = 0; i < lf.length; i++) {
          if (!valuesEqualDeep(lf[i] | 0, rf[i] | 0, seen)) return false;
        }
        return true;
      }
      case TAG_CLOSURE:
        return leftPtr === rightPtr;
      default:
        return intValue(leftPtr) === intValue(rightPtr);
    }
  };

  const valuesEqual = (leftPtr, rightPtr) => valuesEqualDeep(leftPtr, rightPtr, new Set());

  const compareValuesDeep = (leftPtr, rightPtr, seen) => {
    if (leftPtr === rightPtr) return 0;
    const pairKey = `${leftPtr}|${rightPtr}`;
    if (seen.has(pairKey)) return 0;
    seen.add(pairKey);

    const left = readHandle(leftPtr);
    const right = readHandle(rightPtr);
    if (!left || !right) return left ? 1 : right ? -1 : 0;
    if (left.tag !== right.tag) return left.tag < right.tag ? -1 : 1;

    switch (left.tag) {
      case TAG_INT:
        return compareInts(left.value | 0, right.value | 0);
      case TAG_FLOAT:
        return left.value < right.value ? -1 : left.value > right.value ? 1 : 0;
      case TAG_CHAR:
        return compareInts(left.value | 0, right.value | 0);
      case TAG_STRING:
        return left.value < right.value ? -1 : left.value > right.value ? 1 : 0;
      case TAG_ORDER:
        return compareInts(left.value | 0, right.value | 0);
      case TAG_TUPLE2: {
        const firstCmp = compareValuesDeep(left.first | 0, right.first | 0, seen);
        if (firstCmp !== 0) return firstCmp;
        return compareValuesDeep(left.second | 0, right.second | 0, seen);
      }
      case TAG_LIST: {
        const leftItems = listItems(leftPtr);
        const rightItems = listItems(rightPtr);
        const len = Math.max(leftItems.length, rightItems.length);
        for (let i = 0; i < len; i++) {
          const cmp = compareValuesDeep(leftItems[i] ?? 0, rightItems[i] ?? 0, seen);
          if (cmp !== 0) return cmp;
        }
        return 0;
      }
      case TAG_MAYBE: {
        if ((left.value == null) !== (right.value == null)) {
          return left.value == null ? -1 : 1;
        }
        return left.value == null
          ? 0
          : compareValuesDeep(left.value | 0, right.value | 0, seen);
      }
      case TAG_RESULT: {
        if (left.isOk !== right.isOk) return left.isOk ? 1 : -1;
        return compareValuesDeep(left.value | 0, right.value | 0, seen);
      }
      case TAG_RECORD: {
        const lf = left.fields ?? [];
        const rf = right.fields ?? [];
        const len = Math.max(lf.length, rf.length);
        for (let i = 0; i < len; i++) {
          const cmp = compareValuesDeep(lf[i] ?? 0, rf[i] ?? 0, seen);
          if (cmp !== 0) return cmp;
        }
        return 0;
      }
      default:
        return compareInts(intValue(leftPtr), intValue(rightPtr));
    }
  };

  const compareValues = (leftPtr, rightPtr) => compareValuesDeep(leftPtr, rightPtr, new Set());

  const dictPairKey = (entryPtr) => readHandle(entryPtr)?.first ?? 0;
  const dictPairValue = (entryPtr) => readHandle(entryPtr)?.second ?? 0;

  const dictEntries = (dictPtr) =>
    listItems(dictPtr).map((entryPtr) => [dictPairKey(entryPtr), dictPairValue(entryPtr)]);

  const dictInsertSorted = (dictPtr, keyPtr, valuePtr) => {
    const entries = [];
    let inserted = false;

    for (const entryPtr of listItems(dictPtr)) {
      const existingKey = dictPairKey(entryPtr);
      const cmp = compareValues(keyPtr, existingKey);
      if (cmp === 0) {
        entries.push(allocHandle({ tag: TAG_TUPLE2, first: keyPtr, second: valuePtr }));
        inserted = true;
      } else if (!inserted && cmp < 0) {
        entries.push(allocHandle({ tag: TAG_TUPLE2, first: keyPtr, second: valuePtr }));
        entries.push(entryPtr);
        inserted = true;
      } else {
        entries.push(entryPtr);
      }
    }

    if (!inserted) {
      entries.push(allocHandle({ tag: TAG_TUPLE2, first: keyPtr, second: valuePtr }));
    }

    return newList(entries);
  };

  const dictEmptyHandle = () => newList([]);

  const dictFromList = (outPtr, listPtr) => {
    let dict = dictEmptyHandle();
    for (const entryPtr of listItems(listPtr)) {
      const pair = readHandle(entryPtr);
      if (pair?.tag === TAG_TUPLE2) {
        const next = dictInsertSorted(dict, pair.first, pair.second);
        release(dict);
        dict = next;
      }
    }
    writeOut(outPtr, dict);
    return RC_SUCCESS;
  };

  const dictInsert = (outPtr, keyPtr, valuePtr, dictPtr) => {
    writeOut(outPtr, dictInsertSorted(dictPtr, keyPtr, valuePtr));
    return RC_SUCCESS;
  };

  const dictGet = (outPtr, keyPtr, dictPtr) => {
    for (const entryPtr of listItems(dictPtr)) {
      if (valuesEqual(dictPairKey(entryPtr), keyPtr)) {
        return maybeJustOwn(outPtr, dictPairValue(entryPtr));
      }
    }
    return maybeNothing(outPtr);
  };

  const dictMember = (outPtr, keyPtr, dictPtr) => {
    const found = dictEntries(dictPtr).some(([key]) => valuesEqual(key, keyPtr));
    return newBool(outPtr, found);
  };

  const dictSize = (outPtr, dictPtr) => newInt(outPtr, listItems(dictPtr).length);

  const dictRemove = (outPtr, keyPtr, dictPtr) => {
    const kept = listItems(dictPtr).filter((entryPtr) => !valuesEqual(dictPairKey(entryPtr), keyPtr));
    return writeList(outPtr, kept);
  };

  const dictIsEmpty = (outPtr, dictPtr) => newInt(outPtr, listItems(dictPtr).length === 0 ? 1 : 0);

  const dictKeys = (outPtr, dictPtr) => {
    const keys = dictEntries(dictPtr).map(([key]) => key);
    return writeList(outPtr, keys);
  };

  const dictValues = (outPtr, dictPtr) => {
    const values = dictEntries(dictPtr).map(([, value]) => value);
    return writeList(outPtr, values);
  };

  const dictToList = (outPtr, dictPtr) => writeOut(outPtr, dictPtr);

  const dictMapEntries = (dictPtr, mapper) => {
    const entries = listItems(dictPtr).map((entryPtr) => {
      const key = dictPairKey(entryPtr);
      const value = dictPairValue(entryPtr);
      const mapped = mapper(key, value);
      return allocHandle({ tag: TAG_TUPLE2, first: key, second: mapped });
    });
    return newList(entries);
  };

  const dictMap = (outPtr, closurePtr, dictPtr) => {
    const mapped = dictMapEntries(dictPtr, (key, value) => {
      const args = [asHandle(key), asHandle(value)];
      const { rc, value: out } = invokeClosure(closurePtr, args);
      release(args[0]);
      release(args[1]);
      if (rc !== RC_SUCCESS) return value;
      const handle = asHandle(out);
      release(out);
      return handle;
    });
    writeOut(outPtr, mapped);
    return RC_SUCCESS;
  };

  const dictFold = (closurePtr, accPtr, dictPtr, rightToLeft) => {
    const entries = dictEntries(dictPtr);
    const order = rightToLeft ? [...entries].reverse() : entries;
    let acc = accPtr;
    for (const [key, value] of order) {
      const args = [asHandle(key), asHandle(value), asHandle(acc)];
      const { rc, value: out } = invokeClosure(closurePtr, args);
      release(args[0]);
      release(args[1]);
      release(args[2]);
      if (rc !== RC_SUCCESS) return { rc, acc };
      release(acc);
      acc = asHandle(out);
      release(out);
    }
    return { rc: RC_SUCCESS, acc };
  };

  const dictFoldl = (outPtr, closurePtr, accPtr, dictPtr) => {
    const { rc, acc } = dictFold(closurePtr, accPtr, dictPtr, false);
    if (rc !== RC_SUCCESS) return rc;
    writeOut(outPtr, acc);
    return RC_SUCCESS;
  };

  const dictFoldr = (outPtr, closurePtr, accPtr, dictPtr) => {
    const { rc, acc } = dictFold(closurePtr, accPtr, dictPtr, true);
    if (rc !== RC_SUCCESS) return rc;
    writeOut(outPtr, acc);
    return RC_SUCCESS;
  };

  const dictFilter = (outPtr, closurePtr, dictPtr) => {
    const kept = [];
    for (const entryPtr of listItems(dictPtr)) {
      const key = dictPairKey(entryPtr);
      const value = dictPairValue(entryPtr);
      const args = [asHandle(key), asHandle(value)];
      const { rc, value: out } = invokeClosure(closurePtr, args);
      release(args[0]);
      release(args[1]);
      if (rc !== RC_SUCCESS) return rc;
      if (intValue(out) !== 0) kept.push(entryPtr);
      release(out);
    }
    return writeList(outPtr, kept);
  };

  const dictPartition = (outPtr, closurePtr, dictPtr) => {
    const yes = [];
    const no = [];
    for (const entryPtr of listItems(dictPtr)) {
      const key = dictPairKey(entryPtr);
      const value = dictPairValue(entryPtr);
      const args = [asHandle(key), asHandle(value)];
      const { rc, value: out } = invokeClosure(closurePtr, args);
      release(args[0]);
      release(args[1]);
      if (rc !== RC_SUCCESS) return rc;
      if (intValue(out) !== 0) yes.push(entryPtr);
      else no.push(entryPtr);
      release(out);
    }
    return tuple2(outPtr, newList(yes), newList(no));
  };

  const dictUnion = (outPtr, leftPtr, rightPtr) => {
    let out = newList([...listItems(leftPtr)]);
    for (const entryPtr of listItems(rightPtr)) {
      const key = dictPairKey(entryPtr);
      const value = dictPairValue(entryPtr);
      const merged = dictInsertSorted(out, key, value);
      release(out);
      out = merged;
    }
    writeOut(outPtr, out);
    return RC_SUCCESS;
  };

  const dictIntersect = (outPtr, leftPtr, rightPtr) => {
    const rightKeys = new Set(
      dictEntries(rightPtr).map(([key]) => (readHandle(key)?.tag === TAG_STRING ? readHandle(key).value : intValue(key)))
    );
    const kept = listItems(leftPtr).filter((entryPtr) => {
      const key = dictPairKey(entryPtr);
      const token = readHandle(key)?.tag === TAG_STRING ? readHandle(key).value : intValue(key);
      return rightKeys.has(token);
    });
    return writeList(outPtr, kept);
  };

  const dictDiff = (outPtr, leftPtr, rightPtr) => {
    const rightKeys = new Set(
      dictEntries(rightPtr).map(([key]) => (readHandle(key)?.tag === TAG_STRING ? readHandle(key).value : intValue(key)))
    );
    const kept = listItems(leftPtr).filter((entryPtr) => {
      const key = dictPairKey(entryPtr);
      const token = readHandle(key)?.tag === TAG_STRING ? readHandle(key).value : intValue(key);
      return !rightKeys.has(token);
    });
    return writeList(outPtr, kept);
  };

  const dictMerge = (outPtr, leftFnPtr, bothFnPtr, rightFnPtr, leftPtr, rightPtr, resultPtr) => {
    let acc = resultPtr;
    const left = [...listItems(leftPtr)];
    const right = [...listItems(rightPtr)];
    let li = 0;
    let ri = 0;

    while (li < left.length && ri < right.length) {
      const lKey = dictPairKey(left[li]);
      const rKey = dictPairKey(right[ri]);
      const cmp = compareValues(lKey, rKey);
      let args;
      let { rc, value } = { rc: RC_SUCCESS, value: acc };

      if (cmp < 0) {
        args = [asHandle(lKey), asHandle(dictPairValue(left[li])), asHandle(acc)];
        ({ rc, value } = invokeClosure(leftFnPtr, args));
        li += 1;
      } else if (cmp > 0) {
        args = [asHandle(rKey), asHandle(dictPairValue(right[ri])), asHandle(acc)];
        ({ rc, value } = invokeClosure(rightFnPtr, args));
        ri += 1;
      } else {
        args = [
          asHandle(lKey),
          asHandle(dictPairValue(left[li])),
          asHandle(dictPairValue(right[ri])),
          asHandle(acc),
        ];
        ({ rc, value } = invokeClosure(bothFnPtr, args));
        li += 1;
        ri += 1;
      }

      for (const arg of args) release(arg);
      if (rc !== RC_SUCCESS) return rc;
      release(acc);
      acc = asHandle(value);
      release(value);
    }

    while (li < left.length) {
      const lKey = dictPairKey(left[li]);
      const args = [asHandle(lKey), asHandle(dictPairValue(left[li])), asHandle(acc)];
      const result = invokeClosure(leftFnPtr, args);
      for (const arg of args) release(arg);
      if (result.rc !== RC_SUCCESS) return result.rc;
      release(acc);
      acc = asHandle(result.value);
      release(result.value);
      li += 1;
    }

    while (ri < right.length) {
      const rKey = dictPairKey(right[ri]);
      const args = [asHandle(rKey), asHandle(dictPairValue(right[ri])), asHandle(acc)];
      const result = invokeClosure(rightFnPtr, args);
      for (const arg of args) release(arg);
      if (result.rc !== RC_SUCCESS) return result.rc;
      release(acc);
      acc = asHandle(result.value);
      release(result.value);
      ri += 1;
    }

    writeOut(outPtr, acc);
    return RC_SUCCESS;
  };

  const dictSingleton = (outPtr, keyPtr, valuePtr) => {
    writeOut(
      outPtr,
      newList([allocHandle({ tag: TAG_TUPLE2, first: keyPtr, second: valuePtr })])
    );
    return RC_SUCCESS;
  };

  const dictUpdate = (outPtr, keyPtr, closurePtr, dictPtr) => {
    let found = false;
    const updated = [];

    for (const entryPtr of listItems(dictPtr)) {
      const key = dictPairKey(entryPtr);
      const value = dictPairValue(entryPtr);
      if (!valuesEqual(key, keyPtr)) {
        updated.push(entryPtr);
        continue;
      }

      found = true;
      const maybePtr = allocHandle({ tag: TAG_MAYBE, value });
      const { rc, value: out } = invokeClosure(closurePtr, [maybePtr]);
      release(maybePtr);
      if (rc !== RC_SUCCESS) return rc;
      const maybeOut = readHandle(out);
      if (maybeOut?.tag === TAG_MAYBE && maybeOut.value != null) {
        updated.push(allocHandle({ tag: TAG_TUPLE2, first: key, second: maybeOut.value }));
      }
      release(out);
    }

    if (!found) {
      const nothingPtr = allocHandle({ tag: TAG_MAYBE, value: null });
      const { rc, value: out } = invokeClosure(closurePtr, [nothingPtr]);
      release(nothingPtr);
      if (rc !== RC_SUCCESS) return rc;
      const maybeOut = readHandle(out);
      if (maybeOut?.tag === TAG_MAYBE && maybeOut.value != null) {
        let dict = newList(updated);
        const next = dictInsertSorted(dict, keyPtr, maybeOut.value);
        release(dict);
        release(out);
        return writeOut(outPtr, next);
      }
      release(out);
    }

    return writeList(outPtr, updated);
  };

  const setInsertSorted = (setPtr, valuePtr) => {
    const items = listItems(setPtr);
    if (items.some((item) => valuesEqual(item, valuePtr))) return setPtr;
    const out = [];
    let inserted = false;
    for (const item of items) {
      if (!inserted && compareValues(valuePtr, item) < 0) {
        out.push(valuePtr);
        inserted = true;
      }
      out.push(item);
    }
    if (!inserted) out.push(valuePtr);
    return newList(out);
  };

  const setFromList = (outPtr, listPtr) => {
    let set = newList([]);
    for (const item of listItems(listPtr)) {
      const next = setInsertSorted(set, item);
      if (next !== set) release(set);
      set = next;
    }
    writeOut(outPtr, set);
    return RC_SUCCESS;
  };

  const setInsert = (outPtr, valuePtr, setPtr) => {
    writeOut(outPtr, setInsertSorted(setPtr, valuePtr));
    return RC_SUCCESS;
  };

  const setMember = (outPtr, valuePtr, setPtr) => {
    const found = listItems(setPtr).some((item) => valuesEqual(item, valuePtr));
    return newBool(outPtr, found);
  };

  const setSize = (outPtr, setPtr) => newInt(outPtr, listItems(setPtr).length);
  const setRemove = (outPtr, valuePtr, setPtr) => {
    const kept = listItems(setPtr).filter((item) => !valuesEqual(item, valuePtr));
    return writeList(outPtr, kept);
  };
  const setIsEmpty = (outPtr, setPtr) => newInt(outPtr, listItems(setPtr).length === 0 ? 1 : 0);
  const setToList = (outPtr, setPtr) => writeOut(outPtr, setPtr);
  const setUnion = (outPtr, leftPtr, rightPtr) => {
    let out = newList([...listItems(leftPtr)]);
    for (const item of listItems(rightPtr)) {
      const next = setInsertSorted(out, item);
      if (next !== out) release(out);
      out = next;
    }
    writeOut(outPtr, out);
    return RC_SUCCESS;
  };
  const setIntersect = (outPtr, leftPtr, rightPtr) => {
    const kept = listItems(leftPtr).filter((item) =>
      listItems(rightPtr).some((other) => valuesEqual(item, other))
    );
    return writeList(outPtr, kept);
  };
  const setDiff = (outPtr, leftPtr, rightPtr) => {
    const kept = listItems(leftPtr).filter(
      (item) => !listItems(rightPtr).some((other) => valuesEqual(item, other))
    );
    return writeList(outPtr, kept);
  };
  const setMap = (outPtr, closurePtr, setPtr) => {
    const mapped = listItems(setPtr).map((item) => {
      const arg = asHandle(item);
      const { rc, value } = invokeClosure(closurePtr, [arg]);
      release(arg);
      if (rc !== RC_SUCCESS) return item;
      const handle = asHandle(value);
      release(value);
      return handle;
    });
    let out = newList([]);
    for (const item of mapped) {
      const next = setInsertSorted(out, item);
      if (next !== out) release(out);
      out = next;
    }
    writeOut(outPtr, out);
    return RC_SUCCESS;
  };
  const setFold = (closurePtr, accPtr, setPtr, rightToLeft) => {
    const items = rightToLeft ? [...listItems(setPtr)].reverse() : listItems(setPtr);
    let acc = accPtr;
    for (const item of items) {
      const args = [asHandle(item), asHandle(acc)];
      const { rc, value } = invokeClosure(closurePtr, args);
      release(args[0]);
      release(args[1]);
      if (rc !== RC_SUCCESS) return { rc, acc };
      release(acc);
      acc = asHandle(value);
      release(value);
    }
    return { rc: RC_SUCCESS, acc };
  };
  const setFoldl = (outPtr, closurePtr, accPtr, setPtr) => {
    const { rc, acc } = setFold(closurePtr, accPtr, setPtr, false);
    if (rc !== RC_SUCCESS) return rc;
    writeOut(outPtr, acc);
    return RC_SUCCESS;
  };
  const setFoldr = (outPtr, closurePtr, accPtr, setPtr) => {
    const { rc, acc } = setFold(closurePtr, accPtr, setPtr, true);
    if (rc !== RC_SUCCESS) return rc;
    writeOut(outPtr, acc);
    return RC_SUCCESS;
  };
  const setFilter = (outPtr, closurePtr, setPtr) => {
    const kept = [];
    for (const item of listItems(setPtr)) {
      const arg = asHandle(item);
      const { rc, value } = invokeClosure(closurePtr, [arg]);
      release(arg);
      if (rc !== RC_SUCCESS) return rc;
      if (intValue(value) !== 0) kept.push(item);
      release(value);
    }
    return writeList(outPtr, kept);
  };
  const setPartition = (outPtr, closurePtr, setPtr) => {
    const yes = [];
    const no = [];
    for (const item of listItems(setPtr)) {
      const arg = asHandle(item);
      const { rc, value } = invokeClosure(closurePtr, [arg]);
      release(arg);
      if (rc !== RC_SUCCESS) return rc;
      if (intValue(value) !== 0) yes.push(item);
      else no.push(item);
      release(value);
    }
    return tuple2(outPtr, newList(yes), newList(no));
  };
  const setSingleton = (outPtr, valuePtr) => writeList(outPtr, [valuePtr]);

  const arrayEmpty = (outPtr) => writeList(outPtr, []);
  const arrayFromList = (outPtr, listPtr) => {
    writeOut(outPtr, newList([...listItems(listPtr)]));
    return RC_SUCCESS;
  };
  const arrayLength = (outPtr, arrayPtr) => newInt(outPtr, listItems(arrayPtr).length);
  const arrayGet = (outPtr, indexPtr, arrayPtr) => {
    const index = wasmScalarArg(indexPtr);
    const items = listItems(arrayPtr);
    if (index < 0 || index >= items.length) return maybeNothing(outPtr);
    return maybeJustOwn(outPtr, asHandle(items[index]));
  };
  const arraySet = (outPtr, indexPtr, valuePtr, arrayPtr) => {
    const index = wasmScalarArg(indexPtr);
    const items = [...listItems(arrayPtr)];
    if (index < 0 || index >= items.length) {
      writeOut(outPtr, arrayPtr);
      return RC_SUCCESS;
    }
    items[index] = handles.has(valuePtr) ? valuePtr : newIntHandle(wasmScalarArg(valuePtr));
    return writeList(outPtr, items);
  };
  const arrayPush = (outPtr, valuePtr, arrayPtr) => {
    const value = handles.has(valuePtr) ? valuePtr : newIntHandle(wasmScalarArg(valuePtr));
    return writeList(outPtr, [...listItems(arrayPtr), value]);
  };
  const arrayInitialize = (outPtr, countPtr, closurePtr) => {
    const count = wasmScalarArg(countPtr);
    const items = [];
    for (let i = 0; i < count; i++) {
      const { rc, value } = invokeClosure(closurePtr, [newIntHandle(i)]);
      if (rc !== RC_SUCCESS) return rc;
      items.push(asHandle(value));
      release(value);
    }
    return writeList(outPtr, items);
  };
  const arrayRepeat = (outPtr, countPtr, valuePtr) => {
    const count = wasmScalarArg(countPtr);
    const value = handles.has(valuePtr) ? valuePtr : newIntHandle(wasmScalarArg(valuePtr));
    return writeList(outPtr, Array.from({ length: count }, () => value));
  };
  const arrayIsEmpty = (outPtr, arrayPtr) => newInt(outPtr, listItems(arrayPtr).length === 0 ? 1 : 0);
  const arrayToList = (outPtr, arrayPtr) => writeOut(outPtr, arrayPtr);
  const arrayToIndexedList = (outPtr, arrayPtr) => {
    const pairs = listItems(arrayPtr).map((item, index) =>
      allocHandle({ tag: TAG_TUPLE2, first: newIntHandle(index), second: asHandle(item) })
    );
    return writeList(outPtr, pairs);
  };
  const arrayMap = (outPtr, closurePtr, arrayPtr) => {
    const items = [];
    for (const item of listItems(arrayPtr)) {
      const arg = asHandle(item);
      const { rc, value } = invokeClosure(closurePtr, [arg]);
      release(arg);
      if (rc !== RC_SUCCESS) return rc;
      items.push(asHandle(value));
      release(value);
    }
    return writeList(outPtr, items);
  };
  const arrayIndexedMap = (outPtr, closurePtr, arrayPtr) => {
    const items = [];
    listItems(arrayPtr).forEach((item, index) => {
      const args = [newIntHandle(index), asHandle(item)];
      const { rc, value } = invokeClosure(closurePtr, args);
      release(args[0]);
      release(args[1]);
      if (rc !== RC_SUCCESS) return;
      items.push(asHandle(value));
      release(value);
    });
    return writeList(outPtr, items);
  };
  const arrayFoldl = (outPtr, closurePtr, accPtr, arrayPtr) => {
    let acc = accPtr;
    for (const item of listItems(arrayPtr)) {
      const args = [asHandle(item), asHandle(acc)];
      const { rc, value } = invokeClosure(closurePtr, args);
      release(args[0]);
      release(args[1]);
      if (rc !== RC_SUCCESS) return rc;
      release(acc);
      acc = asHandle(value);
      release(value);
    }
    writeOut(outPtr, acc);
    return RC_SUCCESS;
  };
  const arrayFoldr = (outPtr, closurePtr, accPtr, arrayPtr) => {
    let acc = accPtr;
    for (const item of [...listItems(arrayPtr)].reverse()) {
      const args = [asHandle(item), asHandle(acc)];
      const { rc, value } = invokeClosure(closurePtr, args);
      release(args[0]);
      release(args[1]);
      if (rc !== RC_SUCCESS) return rc;
      release(acc);
      acc = asHandle(value);
      release(value);
    }
    writeOut(outPtr, acc);
    return RC_SUCCESS;
  };
  const arrayFilter = (outPtr, closurePtr, arrayPtr) => {
    const kept = [];
    for (const item of listItems(arrayPtr)) {
      const arg = asHandle(item);
      const { rc, value } = invokeClosure(closurePtr, [arg]);
      release(arg);
      if (rc !== RC_SUCCESS) return rc;
      if (intValue(value) !== 0) kept.push(item);
      release(value);
    }
    return writeList(outPtr, kept);
  };
  const arrayAppend = (outPtr, leftPtr, rightPtr) =>
    writeList(outPtr, [...listItems(leftPtr), ...listItems(rightPtr)]);
  const arraySlice = (outPtr, startPtr, endPtr, arrayPtr) => {
    const start = wasmScalarArg(startPtr);
    const end = wasmScalarArg(endPtr);
    return writeList(outPtr, listItems(arrayPtr).slice(start, end));
  };

  const newImmortalString = (outPtr, literalId) => {
    const id = literalId | 0;
    let handle = immortalStringHandles.get(id);
    if (!handle) {
      const text = lookupImmortalString(id);
      handle = allocHandle({ tag: TAG_STRING, value: text, immortal: true, literalId: id });
      immortalStringHandles.set(id, handle);
    }
    writeOut(outPtr, handle);
    return RC_SUCCESS;
  };

  const makeClosure = (outPtr, fnIndex, arity, ...captures) => {
    const captured = [];
    for (const raw of captures) {
      if ((raw | 0) === 0) continue;
      const handle = normalizeFieldHandle(raw);
      if (handles.has(handle | 0)) retain(null, handle);
      captured.push(handle);
    }
    writeOut(
      outPtr,
      allocHandle({
        tag: TAG_CLOSURE,
        fnIndex: fnIndex | 0,
        arity: arity | 0,
        captures: captured,
      })
    );
    return RC_SUCCESS;
  };

  const invokeClosure = (closurePtr, callArgs) => {
    const payload = readHandle(closurePtr);
    if (payload?.tag !== TAG_CLOSURE || typeof invokeClosureExport !== "function") {
      return { rc: RC_SUCCESS, value: newIntHandle(0) };
    }

    const captures = payload.captures ?? [];
    const applied = payload.applied ?? [];
    const nextApplied = [...applied, ...callArgs];
    const need = payload.arity | 0;

    if (nextApplied.length < need) {
      return {
        rc: RC_SUCCESS,
        value: allocHandle({
          tag: TAG_CLOSURE,
          fnIndex: payload.fnIndex | 0,
          arity: need,
          captures,
          applied: nextApplied,
        }),
      };
    }

    const { rc, value } = invokeClosureExport(
      payload.fnIndex,
      captures,
      nextApplied.slice(0, need)
    );
    if (rc !== RC_SUCCESS) return { rc, value: 0 };

    // Elm currying: f a b where arity(f)=1 returns g, then apply b to g.
    // Mirrors elmc_closure_call oversaturation in the C runtime.
    const normalized = normalizeClosureValue(value);
    const remaining = nextApplied.slice(need);
    if (remaining.length === 0) {
      return { rc, value: normalized };
    }

    const continuedPayload = readHandle(normalized);
    if (continuedPayload?.tag !== TAG_CLOSURE) {
      return { rc, value: normalized };
    }

    const continued = invokeClosure(normalized, remaining);
    if (
      normalized &&
      continued.value !== normalized &&
      handles.has(normalized)
    ) {
      release(normalized);
    }
    return continued;
  };

  const normalizeClosureValue = (value) => {
    if (!value) return newIntHandle(0);
    if (handles.has(value)) return value;
    return newIntHandle(intValue(value));
  };

  const callClosure = (outPtr, argc, closurePtr, ...callArgs) => {
    const { rc, value } = invokeClosure(closurePtr, callArgs.slice(0, argc | 0));
    if (rc !== RC_SUCCESS) return rc;
    writeOut(outPtr, value);
    return RC_SUCCESS;
  };

  const mapListWithClosure = (outPtr, closurePtr, listPtr) => {
    const results = [];

    for (const item of listItems(listPtr)) {
      const arg = asHandle(item);
      const { rc, value } = invokeClosure(closurePtr, [arg]);
      if (rc !== RC_SUCCESS) return rc;
      results.push(value);
    }

    return writeList(outPtr, results);
  };

  // List.map2..map5: zip shortest length; pass element handles (not ints) and keep
  // closure results as handles — same ownership shape as list_map / C elmc_list_map2.
  const mapListsWithClosure = (outPtr, closurePtr, listPtrs) => {
    const lists = listPtrs.map(listItems);
    const len = Math.min(...lists.map((items) => items.length));
    const results = [];

    for (let i = 0; i < len; i++) {
      const args = lists.map((items) => asHandle(items[i]));
      const { rc, value } = invokeClosure(closurePtr, args);
      if (rc !== RC_SUCCESS) return rc;
      results.push(value);
    }

    return writeList(outPtr, results);
  };

  const filterListWithClosure = (outPtr, closurePtr, listPtr) => {
    const kept = [];

    for (const item of listItems(listPtr)) {
      const arg = asHandle(item);
      const { rc, value } = invokeClosure(closurePtr, [arg]);
      if (rc !== RC_SUCCESS) return rc;
      if (intValue(value) !== 0) {
        retain(null, item);
        kept.push(item);
      }
      release(value);
    }

    return writeList(outPtr, kept);
  };

  const unboxInt = (handle) => intValue(handle);

  const checkBalanced = () => {
    if (retainCount !== 0) {
      return false;
    }

    for (const payload of handles.values()) {
      if (!payload?.immortal) {
        return false;
      }
    }

    return true;
  };

  const debugRcState = () => {
    const byTag = {};
    let nonImmortal = 0;
    for (const payload of handles.values()) {
      const tag = payload?.tag ?? "unknown";
      byTag[tag] = (byTag[tag] ?? 0) + 1;
      if (!payload?.immortal) nonImmortal += 1;
    }
    return { retainCount, total: handles.size, nonImmortal, byTag };
  };

  const json = createJsonRuntime({
    RC_SUCCESS,
    RC_ERR_UNIMPLEMENTED,
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
    constructorTags,
  });

  const bytes = createBytesRuntime({
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
  });

  const parser = createParserRuntime({
    RC_SUCCESS,
    RC_ERR_UNIMPLEMENTED,
    writeOut,
    intValue,
    newIntHandle,
    newCharHandle,
    invokeClosure,
    tuple2,
    stringValue,
  });

  const taskRuntime = createTaskRuntime({
    RC_SUCCESS,
    RC_ERR_UNIMPLEMENTED,
    allocHandle,
    readHandle,
    writeOut,
    intValue,
    stringValue,
    invokeClosure,
    tuple2,
    tupleFirst,
    tupleSecond,
    newIntHandle,
    newStringHandle,
    cmdNoneHandle,
    TAG_TUPLE2,
    TAG_INT,
    TAG_RESULT,
    TAG_CMD,
    TAG_RECORD,
    TAG_LIST,
    TAG_MAYBE,
    dispatchPlatformMsg,
    jsonDecodeRunString: json.jsonDecodeRunString,
    readOutSlot: (slot) => readHandle(view().getUint32(slot, true)),
    jsonBodyTextFromValue: (valuePtr) => JSON.stringify(json.unwrapJsonValue(valuePtr)),
    bytesDecodeRun: (outPtr, decoderPtr, bytesPtr) =>
      bytes.bytesDecode(outPtr, decoderPtr, bytesPtr),
    newBytesFromView: (view) => bytes.newBytesHandle(view),
    bytesView: (ptr) => bytes.bytesView(ptr),
    fetchFn: typeof fetch !== "undefined" ? fetch.bind(globalThis) : null,
    newList,
    unitHandle: UNIT_HANDLE,
    constructorTags,
    jsonDecodeErrorToString: json.decodeErrorToString,
  });

  const http = createHttpRuntime({
    RC_SUCCESS,
    RC_ERR_UNIMPLEMENTED,
    allocHandle,
    readHandle,
    writeOut,
    intValue,
    stringValue,
    listItems,
    tuple2,
    newIntHandle,
    newStringHandle,
    newList,
    invokeClosure,
    retain,
    release,
    unitHandle: UNIT_HANDLE,
    TAG_RECORD,
    TAG_LIST,
    TAG_STRING,
    TAG_INT,
    TAG_CMD,
    TAG_RESULT,
    TAG_TUPLE2,
    taskSucceed: taskRuntime.taskSucceed,
    taskFail: taskRuntime.taskFail,
    cmdNoneHandle,
  });

  const fileRuntime = createFileRuntime({
    RC_SUCCESS,
    allocHandle,
    readHandle,
    writeOut,
    stringValue,
    newList,
    newStringHandle,
    cmdNoneHandle,
    writeTaskSucceed: taskRuntime.taskSucceed,
    unitValue: () => newIntHandle(0),
    TAG_RECORD,
    TAG_STRING,
    TAG_CMD,
    invokeClosure,
    dispatchPlatformMsg,
  });

  const resultOkHandle = (valueHandle) =>
    allocHandle({ tag: TAG_RESULT, isOk: true, value: valueHandle | 0 });

  const resultErrHandle = (valueHandle) =>
    allocHandle({ tag: TAG_RESULT, isOk: false, value: valueHandle | 0 });

  const randomRuntime = createRandomRuntime({
    RC_SUCCESS,
    allocHandle,
    readHandle,
    writeOut,
    intValue,
    invokeClosure,
    cmdNoneHandle,
    TAG_CMD,
    TAG_RESULT,
    TAG_CLOSURE,
    newIntHandle,
    dispatchPlatformMsg,
  });

  const regexRuntime = createRegexRuntime({
    RC_SUCCESS,
    writeOut,
    stringValue,
    maybeJustOwn,
    maybeNothing,
    newStringHandle,
    newIntHandle,
    readHandle,
    newList,
    resultOk: resultOkHandle,
    resultErr: resultErrHandle,
    TAG_STRING,
    TAG_RECORD,
    allocHandle,
  });

  http.setDispatchMsg(dispatchPlatformMsg);

  const drainPlatformCommands = async (cmdPtr) => {
    const ptr = cmdPtr | 0;
    if (!ptr || cmdCellIsNone(ptr)) return;

    const payload = readHandle(ptr);
    if (!payload) return;

    if (payload.tag === TAG_CMD) {
      if (payload.kind === "http") {
        await http.drainHttpCommands(ptr, bytes);
        return;
      }
      if (payload.kind === "task") {
        await taskRuntime.drainTaskCmd(ptr);
        return;
      }
      if (payload.kind === "random_generate") {
        randomRuntime.drainRandomCommands(ptr);
        return;
      }
      fileRuntime.drainFileCommands(ptr);
      return;
    }

    if (payload.tag === TAG_RECORD) {
      const tag = intValue(payload.fields[0]);
      if (tag === 2) {
        for (const item of listItems(payload.fields[1] | 0)) {
          await drainPlatformCommands(item);
        }
        return;
      }
      if (tag === 3) {
        await drainPlatformCommands(payload.fields[2] | 0);
      }
    }
  };

  cloneIncomingPortPayload = (payloadPtr) => {
    const ptr = payloadPtr | 0;
    if (!ptr) return ptr;
    const payload = readHandle(ptr);
    if (!payload) return ptr;
    if (payload.tag === bytes.TAG_BYTES && payload.view) {
      const copy = new Uint8Array(payload.view.byteLength);
      copy.set(
        new Uint8Array(payload.view.buffer, payload.view.byteOffset, payload.view.byteLength)
      );
      return bytes.newBytesHandle(new DataView(copy.buffer));
    }
    return cloneHandleForProgram(ptr);
  };

  deliverIncomingPortFn = async (portName, payloadInput) => {
    if (!liveBrowser) return { rc: RC_ERR_UNIMPLEMENTED, modelPtr: 0 };
    let payloadPtr = payloadInput | 0;
    if (payloadInput instanceof Uint8Array) {
      payloadPtr = bytes.newBytesHandle(
        new DataView(payloadInput.buffer, payloadInput.byteOffset, payloadInput.byteLength)
      );
    }
    const initFn = recordField(liveBrowser.implPtr, 0);
    const applied = applyIncomingPorts(liveBrowser.implPtr, initFn, liveBrowser.modelPtr, {
      [portName]: payloadPtr,
    });
    if (applied.rc !== RC_SUCCESS) return applied;
    liveBrowser.modelPtr = applied.modelPtr | 0;
    const viewResult = invokeClosure(liveBrowser.viewFn, [liveBrowser.modelPtr]);
    if (viewResult.rc === RC_SUCCESS) {
      mountViewHandle(viewResult.value);
    }
    return applied;
  };

  navigationRuntime = createNavigationRuntime({
    RC_SUCCESS,
    invokeClosure,
    dispatchPlatformMsg,
    newIntHandle,
    readHandle,
    unionTagAsInt,
    urlRuntime: urlRuntimeApi,
    routeBytes: routeBytesRuntime,
    deliverIncomingPort: deliverIncomingPortFn,
  });

  const bootUrlFromEnvironment = () => {
    if (typeof window !== "undefined" && urlRuntimeApi) {
      return urlRuntimeApi.urlFromLocation(window.location);
    }
    return urlRuntimeApi.urlFromParts({
      protocol: "http:",
      host: "localhost",
      port: "",
      pathname: "/",
      search: "",
      hash: "",
    });
  };

  const BOOT_INPUT_SCRATCH = 8192;
  createDefaultBootInputs = () => {
    const url = bootUrlFromEnvironment();
    const key = navigationRuntime ? navigationRuntime.newNavigationKey() : newIntHandle(1);

    if (!memory) {
      return { flags: 0, url, key };
    }

    json.jsonCmd(BOOT_INPUT_SCRATCH, 7);
    const flags = view().getUint32(BOOT_INPUT_SCRATCH, true);
    return { flags, url, key };
  };

  const implementations = {
    retain,
    release,
    release_unless_reachable: releaseUnlessReachable,
    release_unless_reachable_from_roots: releaseUnlessReachableFromRoots,
    release_array_lifo: releaseArrayLifo,
    as_int: asIntNumber,
    as_bool: asBoolForWasm,
    // Scalar value import: wasm switch lowering calls (union_tag_as_int handle) -> i32.
    union_tag_as_int: unionTagAsInt,
    union_tag_matches: unionTagMatches,
    union_payload: (outPtr, handlePtr) => {
      const payload = readHandle(handlePtr);
      if (payload?.tag === TAG_TUPLE2) {
        writeOut(outPtr, payload.second | 0);
        retain(null, payload.second | 0);
      } else {
        writeOut(outPtr, handlePtr | 0);
        retain(null, handlePtr | 0);
      }
      return RC_SUCCESS;
    },
    as_float: asFloatBits,
    float_div_bits: floatDivBits,
    new_int: newInt,
    new_bool: newBool,
    new_float: newFloat,
    list_nil: listNil,
    list_from_int_array: listFromIntArray,
    list_append: listAppend,
    list_concat: listConcat,
    list_length: listLength,
    list_sum: listSum,
    list_product: listProduct,
    list_reverse: listReverse,
    list_head: listHead,
    list_tail: listTail,
    list_take: listTake,
    list_drop: listDrop,
    list_range: listRange,
    list_repeat: listRepeat,
    list_singleton: listSingleton,
    list_cons: listCons,
    list_member: listMember,
    list_is_empty: listIsEmpty,
    list_maximum: listMaximum,
    list_minimum: listMinimum,
    list_intersperse: listIntersperse,
    list_sort: listSort,
    list_sort_by: listSortBy,
    list_sort_with: listSortWith,
    list_foldl: listFoldl,
    list_foldr: listFoldr,
    list_any: listAny,
    list_all: listAll,
    maybe_nothing: maybeNothing,
    unit,
    maybe_just_own: maybeJustOwn,
    maybe_just_payload: maybeJustPayload,
    maybe_is_nothing: maybeIsNothing,
    maybe_with_default: maybeWithDefault,
    maybe_map: maybeMap,
    maybe_map2: maybeMap2,
    maybe_and_then: maybeAndThen,
    basics_compare: basicsCompare,
    basics_not: basicsNot,
    new_order: newOrder,
    basics_abs: basicsAbs,
    basics_acos: basicsAcos,
    basics_asin: basicsAsin,
    basics_atan: basicsAtan,
    basics_atan2: basicsAtan2,
    basics_ceiling: basicsCeiling,
    basics_clamp: basicsClamp,
    basics_cos: basicsCos,
    basics_degrees: basicsDegrees,
    basics_floor: basicsFloor,
    basics_from_polar: basicsFromPolar,
    basics_is_infinite: basicsIsInfinite,
    basics_is_nan: basicsIsNan,
    basics_log_base: basicsLogBase,
    basics_max: basicsMax,
    basics_min: basicsMin,
    basics_mod_by: basicsModBy,
    basics_negate: basicsNegate,
    basics_radians: basicsRadians,
    basics_remainder_by: basicsRemainderBy,
    basics_round: basicsRound,
    basics_sin: basicsSin,
    basics_sqrt: basicsSqrt,
    basics_tan: basicsTan,
    basics_to_float: basicsToFloat,
    basics_to_polar: basicsToPolar,
    basics_truncate: basicsTruncate,
    basics_turns: basicsTurns,
    basics_xor: basicsXor,
    char_from_code: charFromCode,
    char_to_lower: charToLower,
    char_is_upper: charIsUpper,
    char_is_lower: charIsLower,
    char_is_alpha_num: charIsAlphaNum,
    char_is_oct_digit: charIsOctDigit,
    char_is_hex_digit: charIsHexDigit,
    bitwise_and: bitwiseAnd,
    bitwise_or: bitwiseOr,
    bitwise_xor: bitwiseXor,
    bitwise_complement: bitwiseComplement,
    bitwise_shift_left_by: bitwiseShiftLeftBy,
    bitwise_shift_right_by: bitwiseShiftRightBy,
    bitwise_shift_right_zf_by: bitwiseShiftRightZfBy,
    debug_log: debugLog,
    debug_todo: debugTodo,
    debug_to_string: debugToString,
    dict_diff: dictDiff,
    dict_filter: dictFilter,
    dict_foldl: dictFoldl,
    dict_foldr: dictFoldr,
    dict_from_list: dictFromList,
    dict_get: dictGet,
    dict_insert: dictInsert,
    dict_intersect: dictIntersect,
    dict_is_empty: dictIsEmpty,
    dict_keys: dictKeys,
    dict_map: dictMap,
    dict_member: dictMember,
    dict_merge: dictMerge,
    dict_partition: dictPartition,
    dict_remove: dictRemove,
    dict_singleton: dictSingleton,
    dict_size: dictSize,
    dict_to_list: dictToList,
    dict_union: dictUnion,
    dict_update: dictUpdate,
    dict_values: dictValues,
    set_diff: setDiff,
    set_filter: setFilter,
    set_foldl: setFoldl,
    set_foldr: setFoldr,
    set_from_list: setFromList,
    set_insert: setInsert,
    set_intersect: setIntersect,
    set_is_empty: setIsEmpty,
    set_map: setMap,
    set_member: setMember,
    set_partition: setPartition,
    set_remove: setRemove,
    set_singleton: setSingleton,
    set_size: setSize,
    set_to_list: setToList,
    set_union: setUnion,
    array_append: arrayAppend,
    array_empty: arrayEmpty,
    array_filter: arrayFilter,
    array_foldl: arrayFoldl,
    array_foldr: arrayFoldr,
    array_from_list: arrayFromList,
    array_get: arrayGet,
    array_indexed_map: arrayIndexedMap,
    array_initialize: arrayInitialize,
    array_is_empty: arrayIsEmpty,
    array_length: arrayLength,
    array_map: arrayMap,
    array_push: arrayPush,
    array_repeat: arrayRepeat,
    array_set: arraySet,
    array_slice: arraySlice,
    array_to_indexed_list: arrayToIndexedList,
    array_to_list: arrayToList,
    task_succeed: taskRuntime.taskSucceed,
    task_fail: taskRuntime.taskFail,
    task_map: taskRuntime.taskMap,
    task_map2: taskRuntime.taskMap2,
    task_and_then: taskRuntime.taskAndThen,
    task_on_error: taskRuntime.taskOnError,
    task_perform: taskRuntime.taskPerform,
    backend_task_http_get_json: taskRuntime.backendTaskHttpGetJson,
    backend_task_http_get: taskRuntime.backendTaskHttpGet,
    backend_task_http_expect_json: taskRuntime.backendTaskHttpExpectJson,
    backend_task_http_expect_string: taskRuntime.backendTaskHttpExpectString,
    backend_task_http_expect_whatever: taskRuntime.backendTaskHttpExpectWhatever,
    backend_task_http_expect_bytes: taskRuntime.backendTaskHttpExpectBytes,
    backend_task_http_with_metadata: taskRuntime.backendTaskHttpWithMetadata,
    backend_task_http_empty_body: taskRuntime.backendTaskHttpEmptyBody,
    backend_task_http_string_body: taskRuntime.backendTaskHttpStringBody,
    backend_task_http_json_body: taskRuntime.backendTaskHttpJsonBody,
    backend_task_http_bytes_body: taskRuntime.backendTaskHttpBytesBody,
    backend_task_http_request: taskRuntime.backendTaskHttpRequest,
    backend_task_http_post: taskRuntime.backendTaskHttpPost,
    backend_task_http_get_with_options: taskRuntime.backendTaskHttpGetWithOptions,
    time_now_millis: taskRuntime.timeNowMillis,
    time_zone_offset_minutes: (outPtr) => {
      const jsOffset = typeof Date !== "undefined" ? new Date().getTimezoneOffset() : 0;
      writeOut(outPtr, newIntHandle(-jsOffset));
      return RC_SUCCESS;
    },
    time_here: (outPtr) => {
      const jsOffset = typeof Date !== "undefined" ? new Date().getTimezoneOffset() : 0;
      const zone = allocHandle({
        tag: TAG_RECORD,
        fields: [newStringHandle("here"), newIntHandle(-jsOffset)],
      });
      writeOut(outPtr, zone);
      return RC_SUCCESS;
    },
    browser_get_viewport: (outPtr) => {
      const w = typeof window !== "undefined" ? window.innerWidth | 0 : 0;
      const h = typeof window !== "undefined" ? window.innerHeight | 0 : 0;
      const scene = allocHandle({
        tag: TAG_RECORD,
        fields: [newIntHandle(w), newIntHandle(h)],
      });
      const viewport = allocHandle({
        tag: TAG_RECORD,
        fields: [newIntHandle(0), newIntHandle(0), newIntHandle(w), newIntHandle(h)],
      });
      const domViewport = allocHandle({ tag: TAG_RECORD, fields: [scene, viewport] });
      return taskRuntime.taskSucceed(outPtr, domViewport);
    },
    url_from_string: (outPtr, urlPtr) => {
      const parsed = urlRuntimeApi.urlFromString(stringValue(urlPtr | 0));
      writeOut(outPtr, parsed);
      return RC_SUCCESS;
    },
    process_spawn: taskRuntime.processSpawn,
    process_sleep: taskRuntime.processSleep,
    process_kill: taskRuntime.processKill,
    url_percent_encode: (outPtr, segmentPtr) => {
      const encoded = encodeURIComponent(stringValue(segmentPtr));
      writeOut(outPtr, newStringHandle(encoded));
      return RC_SUCCESS;
    },
    url_percent_decode: (outPtr, segmentPtr) => {
      try {
        const decoded = decodeURIComponent(stringValue(segmentPtr));
        writeOut(outPtr, newStringHandle(decoded));
        return RC_SUCCESS;
      } catch (_err) {
        writeOut(outPtr, segmentPtr | 0);
        retain(null, segmentPtr | 0);
        return RC_SUCCESS;
      }
    },
    http_empty_body: http.httpEmptyBody,
    http_pair: http.httpPair,
    http_to_data_view: http.httpToDataView,
    http_expect: http.httpExpect,
    http_command: http.httpCommand,
    http_cancel: http.httpCancel,
    file_select: fileRuntime.fileSelect,
    file_download: fileRuntime.fileDownload,
    file_download_task: fileRuntime.fileDownloadTask,
    random_generate: randomRuntime.randomGenerate,
    regex_from_string: regexRuntime.regexFromString,
    regex_find: regexRuntime.regexFind,
    regex_contains: regexRuntime.regexContains,
    regex_replace: regexRuntime.regexReplace,
    // WASM call_runtime emits (out, prefix/suffix, str) for these imports — opposite of
    // the elmc_string_chop_* C symbol parameter order in special_values.
    string_chop_end: (outPtr, suffixPtr, strPtr) => {
      const str = stringValue(strPtr);
      const suffix = stringValue(suffixPtr);
      const out =
        suffix && str.endsWith(suffix) ? str.slice(0, str.length - suffix.length) : str;
      writeOut(outPtr, newStringHandle(out));
      return RC_SUCCESS;
    },
    string_chop_start: (outPtr, prefixPtr, strPtr) => {
      const str = stringValue(strPtr);
      const prefix = stringValue(prefixPtr);
      const out = prefix && str.startsWith(prefix) ? str.slice(prefix.length) : str;
      writeOut(outPtr, newStringHandle(out));
      return RC_SUCCESS;
    },
    string_chop_forward_slashes: (outPtr, strPtr) => {
      const out = stringValue(strPtr).replace(/\\/g, "/").replace(/\/+/g, "/");
      writeOut(outPtr, newStringHandle(out));
      return RC_SUCCESS;
    },
    record_new: recordNew,
    record_new_values_ints: recordNewValuesInts,
    record_get: recordGet,
    record_update: recordUpdate,
    list_nth_maybe: listNthMaybe,
    list_nth_int_default: listNthIntDefault,
    list_replace_nth_int: listReplaceNthInt,
    list_slice_int: listSliceInt,
    int_list_head_int: intListHeadInt,
    int_list_tail: intListTail,
    tuple2_ints: tuple2Ints,
    tuple_first: runtimeTupleFirst,
    tuple_second: runtimeTupleSecond,
    tuple_proj: tupleProj,
    tuple_map_first: tupleMapFirst,
    tuple_map_second: tupleMapSecond,
    tuple_map_both: tupleMapBoth,
    result_ok_own: resultOkOwn,
    result_err_own: resultErrOwn,
    result_with_default: resultWithDefault,
    result_map: resultMap,
    result_map_error: resultMapError,
    result_and_then: resultAndThen,
    result_to_maybe: resultToMaybe,
    result_from_maybe: resultFromMaybe,
    string_append: stringAppend,
    append,
    new_char: newChar,
    string_length_boxed: stringLengthBoxed,
    string_length_val: stringLengthVal,
    string_is_empty: stringIsEmpty,
    string_reverse: stringReverse,
    string_repeat: stringRepeat,
    string_replace: stringReplace,
    string_from_int_value: stringFromIntValue,
    string_to_int: stringToInt,
    string_from_float: stringFromFloat,
    string_to_float: stringToFloat,
    string_to_upper: stringToUpper,
    string_to_lower: stringToLower,
    string_trim: stringTrim,
    string_trim_left: stringTrimLeft,
    string_trim_right: stringTrimRight,
    string_contains: stringContains,
    string_starts_with: stringStartsWith,
    string_ends_with: stringEndsWith,
    string_split: stringSplit,
    string_equals: stringEquals,
    string_equals_literal: stringEqualsLiteral,
    string_join: stringJoin,
    string_words: stringWords,
    string_lines: stringLines,
    string_slice: stringSlice,
    string_left: stringLeft,
    string_right: stringRight,
    string_drop_left: stringDropLeft,
    string_drop_right: stringDropRight,
    string_cons: stringCons,
    string_uncons: stringUncons,
    string_to_list: stringToList,
    string_from_list: stringFromList,
    string_from_char: stringFromChar,
    string_pad: stringPad,
    string_pad_left: stringPadLeft,
    string_pad_right: stringPadRight,
    string_map: stringMap,
    string_filter: stringFilter,
    string_foldl: stringFoldl,
    string_foldr: stringFoldr,
    string_any: stringAny,
    string_all: stringAll,
    string_indexes: stringIndexes,
    char_to_code: charToCode,
    char_to_upper: charToUpper,
    char_is_alpha: charIsAlpha,
    char_is_digit: charIsDigit,
    new_immortal_string: newImmortalString,
    make_closure: makeClosure,
    call_closure: callClosure,
    list_map: mapListWithClosure,
    list_map2: (outPtr, closurePtr, aPtr, bPtr) =>
      mapListsWithClosure(outPtr, closurePtr, [aPtr, bPtr]),
    list_map3: (outPtr, closurePtr, aPtr, bPtr, cPtr) =>
      mapListsWithClosure(outPtr, closurePtr, [aPtr, bPtr, cPtr]),
    list_map4: (outPtr, closurePtr, aPtr, bPtr, cPtr, dPtr) =>
      mapListsWithClosure(outPtr, closurePtr, [aPtr, bPtr, cPtr, dPtr]),
    list_map5: (outPtr, closurePtr, aPtr, bPtr, cPtr, dPtr, ePtr) =>
      mapListsWithClosure(outPtr, closurePtr, [aPtr, bPtr, cPtr, dPtr, ePtr]),
    list_filter: filterListWithClosure,
    list_filter_map: filterMapListWithClosure,
    list_indexed_map: (outPtr, closurePtr, listPtr) => {
      const results = [];
      const items = listItems(listPtr);

      for (let index = 0; index < items.length; index++) {
        const indexHandle = newIntHandle(index);
        const { rc, value } = invokeClosure(closurePtr, [
          indexHandle,
          asHandle(items[index]),
        ]);
        release(indexHandle);
        if (rc !== RC_SUCCESS) return rc;
        results.push(value);
      }

      return writeList(outPtr, results);
    },
    list_concat_map: (outPtr, closurePtr, listPtr) => {
      const results = [];

      for (const item of listItems(listPtr)) {
        const arg = asHandle(item);
        const { rc, value } = invokeClosure(closurePtr, [arg]);
        release(arg);
        if (rc !== RC_SUCCESS) return rc;
        for (const mapped of listItems(value)) results.push(mapped);
        release(value);
      }

      return writeList(outPtr, results);
    },
    list_partition: (outPtr, closurePtr, listPtr) => {
      const yes = [];
      const no = [];

      for (const item of listItems(listPtr)) {
        const arg = asHandle(item);
        const { rc, value } = invokeClosure(closurePtr, [arg]);
        release(arg);
        if (rc !== RC_SUCCESS) return rc;
        if (intValue(value) !== 0) yes.push(item);
        else no.push(item);
        release(value);
      }

      const yesList = newList(yes);
      const noList = newList(no);
      return tuple2(outPtr, yesList, noList);
    },
    list_unzip: (outPtr, listPtr) => {
      const left = [];
      const right = [];

      for (const item of listItems(listPtr)) {
        const [a, b] = tuplePairItems(item);
        left.push(a);
        right.push(b);
      }

      return tuple2(outPtr, newList(left), newList(right));
    },
    list_from_values: listFromValues,
    tuple2,
    html_cmd: (outPtr, kindPtr, ...params) => {
      const kind = wasmScalarArg(kindPtr);

      if (kind === HTML_KIND_CMD_NONE) {
        writeOut(outPtr, newIntHandle(0));
        return RC_SUCCESS;
      }

      if (kind === HTML_KIND_TEXT) {
        const textPtr = params[0] | 0;
        const handle = newVdomText(stringValue(textPtr));
        writeOut(outPtr, handle);
        return RC_SUCCESS;
      }

      if (kind === HTML_KIND_ATTR) {
        const keyPtr = params[0] | 0;
        const valuePtr = params[1] | 0;
        const handle = newVdomAttr(stringValue(keyPtr), stringValue(valuePtr));
        writeOut(outPtr, handle);
        return RC_SUCCESS;
      }

      if (kind === HTML_KIND_PROPERTY) {
        const keyPtr = params[0] | 0;
        const valuePtr = params[1] | 0;
        const handle = newVdomProperty(stringValue(keyPtr), stringValue(valuePtr));
        writeOut(outPtr, handle);
        return RC_SUCCESS;
      }

      if (kind === HTML_KIND_STYLE) {
        const propPtr = params[0] | 0;
        const valPtr = params[1] | 0;
        const handle = newVdomAttr("style", `${stringValue(propPtr)}: ${stringValue(valPtr)};`);
        writeOut(outPtr, handle);
        return RC_SUCCESS;
      }

      if (kind === HTML_KIND_MAP) {
        const mapperPtr = params[0] | 0;
        const childPtr = params[1] | 0;
        if (!childPtr) {
          writeOut(outPtr, asHandle(mapperPtr));
          return RC_SUCCESS;
        }
        const child = asHandle(childPtr);
        const mapper = asHandle(mapperPtr);
        // Nesting builders must retain every nested handle — caller's owned
        // shadows may be transfer-nulled / released at epilogue.
        if (handles.has(child)) retain(null, child);
        if (handles.has(mapper)) retain(null, mapper);
        writeOut(
          outPtr,
          allocHandle({
            tag: TAG_VDOM,
            kind: "map",
            mapper: mapper | 0,
            child,
          })
        );
        return RC_SUCCESS;
      }

      if (kind === HTML_KIND_LAZY) {
        const fnPtr = params[0] | 0;
        const argPtr = params[1] | 0;
        writeOut(
          outPtr,
          allocHandle({ tag: TAG_VDOM, kind: "lazy", fn: fnPtr, args: [argPtr | 0] })
        );
        return RC_SUCCESS;
      }

      if (kind === HTML_KIND_LAZY2 || kind === HTML_KIND_LAZY3 || kind === HTML_KIND_LAZY4) {
        const fnPtr = params[0] | 0;
        const argCount = kind - HTML_KIND_LAZY + 1;
        const argPtrs = params.slice(1, 1 + argCount).map((p) => p | 0);
        writeOut(
          outPtr,
          allocHandle({ tag: TAG_VDOM, kind: "lazy", fn: fnPtr, args: argPtrs })
        );
        return RC_SUCCESS;
      }

      if (kind === HTML_KIND_KEYED) {
        const tagPtr = params[0] | 0;
        const keyedPtr = params[1] | 0;
        const keyedChildren = keyedChildrenFromList(keyedPtr);
        const handle = newVdomNode(
          stringValue(tagPtr),
          [],
          keyedChildren.map((entry) => entry.child),
          null,
          keyedChildren
        );
        writeOut(outPtr, handle);
        return RC_SUCCESS;
      }

      if (kind === HTML_KIND_KEYED_NS) {
        const nsPtr = params[0] | 0;
        const tagPtr = params[1] | 0;
        const keyedPtr = params[2] | 0;
        const keyedChildren = keyedChildrenFromList(keyedPtr);
        const handle = newVdomNode(
          stringValue(tagPtr),
          [],
          keyedChildren.map((entry) => entry.child),
          stringValue(nsPtr),
          keyedChildren
        );
        writeOut(outPtr, handle);
        return RC_SUCCESS;
      }

      if (kind === HTML_KIND_NODE) {
        const tagPtr = params[0] | 0;
        const attrsPtr = params[1] | 0;
        const childrenPtr = params[2] | 0;
        const attrs = attrsFromList(attrsPtr);
        const children = listItems(childrenPtr).map((item) => adoptVdom(item));
        const handle = newVdomNode(stringValue(tagPtr), attrs, children);
        writeOut(outPtr, handle);
        return RC_SUCCESS;
      }

      if (kind === HTML_KIND_NODE_NS) {
        const nsPtr = params[0] | 0;
        const tagPtr = params[1] | 0;
        const attrsPtr = params[2] | 0;
        const childrenPtr = params[3] | 0;
        const attrs = attrsFromList(attrsPtr);
        const children = listItems(childrenPtr).map((item) => adoptVdom(item));
        const handle = newVdomNode(
          stringValue(tagPtr),
          attrs,
          children,
          stringValue(nsPtr)
        );
        writeOut(outPtr, handle);
        return RC_SUCCESS;
      }

      if (kind === HTML_KIND_EVENT) {
        const aPtr = params[0] | 0;
        const bPtr = params[1] | 0;
        const cPtr = params[2] | 0;
        if (cPtr) {
          writeOut(outPtr, newVdomEvent(stringValue(aPtr), cPtr | 0, bPtr | 0));
        } else {
          writeOut(outPtr, newVdomEvent(stringValue(aPtr), bPtr | 0, 0));
        }
        return RC_SUCCESS;
      }

      console.warn("[elmc-wasm-runtime] html_cmd unimplemented kind", kind, { params });
      writeOut(outPtr, 0);
      return RC_ERR_UNIMPLEMENTED;
    },
    browser_cmd: (outPtr, kindPtr, ...params) => {
      const kind = wasmScalarArg(kindPtr);

      if (kind === BROWSER_KIND_APPLICATION || kind === BROWSER_KIND_ELEMENT || kind === BROWSER_KIND_DOCUMENT || kind === BROWSER_KIND_WORKER) {
        const implPtr = cloneRecordHandle(params[0] | 0);
        writeOut(outPtr, newBrowserProgram(implPtr));
        return RC_SUCCESS;
      }

      if (kind === BROWSER_KIND_LOAD) {
        const urlPtr = params[0] | 0;
        if (typeof window !== "undefined" && urlPtr) {
          try {
            window.location.assign(stringValue(urlPtr));
          } catch (_err) {
            window.location.reload();
          }
        }
        writeOut(outPtr, cmdNoneHandle());
        return RC_SUCCESS;
      }

      if (kind === BROWSER_KIND_PUSH_URL || kind === BROWSER_KIND_REPLACE_URL) {
        const urlPtr = (params[1] ?? params[0]) | 0;
        if (typeof window !== "undefined" && urlPtr) {
          const pending = navigationRuntime?.consumePendingPushUrl?.();
          let url = pending || normalizePushUrl(stringValue(urlPtr));
          if (kind === BROWSER_KIND_PUSH_URL) {
            window.history.pushState({}, "", url);
          } else {
            window.history.replaceState({}, "", url);
          }
          navigationRuntime?.notifyUrlChangeAfterPush?.();
        }
        writeOut(outPtr, cmdNoneHandle());
        return RC_SUCCESS;
      }

      if (kind === BROWSER_KIND_BACK) {
        if (typeof window !== "undefined") {
          window.history.back();
        }
        writeOut(outPtr, cmdNoneHandle());
        return RC_SUCCESS;
      }

      if (kind === BROWSER_KIND_FORWARD) {
        if (typeof window !== "undefined") {
          window.history.forward();
        }
        writeOut(outPtr, cmdNoneHandle());
        return RC_SUCCESS;
      }

      if (kind === BROWSER_KIND_SET_VIEWPORT) {
        const xPtr = params[0] | 0;
        const yPtr = params[1] | 0;
        if (typeof window !== "undefined") {
          window.scroll(wasmScalarArg(xPtr), wasmScalarArg(yPtr));
        }
        writeOut(outPtr, cmdNoneHandle());
        return RC_SUCCESS;
      }

      if (kind === BROWSER_KIND_FOCUS) {
        const idPtr = params[0] | 0;
        if (typeof document !== "undefined" && idPtr) {
          const el = document.getElementById(stringValue(idPtr));
          if (el && typeof el.focus === "function") el.focus();
        }
        writeOut(outPtr, cmdNoneHandle());
        return RC_SUCCESS;
      }

      if (kind === BROWSER_KIND_SET_TITLE) {
        const titlePtr = params[0] | 0;
        if (typeof document !== "undefined" && titlePtr) {
          document.title = stringValue(titlePtr);
        }
        writeOut(outPtr, cmdNoneHandle());
        return RC_SUCCESS;
      }

      console.warn("[elmc-wasm-runtime] browser_cmd unimplemented kind", kind, { params });
      writeOut(outPtr, cmdNoneHandle());
      return RC_SUCCESS;
    },
    dom_sub: (outPtr, kindPtr, ...params) => {
      const kind = wasmScalarArg(kindPtr);
      if (kind === DOM_SUB_NONE) {
        writeOut(outPtr, newIntHandle(0));
        return RC_SUCCESS;
      }
      const subHandle = allocHandle({
        tag: TAG_SUB,
        domKind: kind | 0,
        params: params.map((p) => p | 0),
      });
      writeOut(outPtr, subHandle);
      return RC_SUCCESS;
    },
    json_cmd: (outPtr, kindPtr, ...params) => json.jsonCmd(outPtr, wasmScalarArg(kindPtr), ...params),
    bytes_cmd: (outPtr, kindPtr, ...params) => bytes.bytesCmd(outPtr, wasmScalarArg(kindPtr), ...params),
    parser_cmd: (outPtr, kindPtr, ...params) => parser.parserCmd(outPtr, wasmScalarArg(kindPtr), ...params),
    bytes_from_list: (outPtr, listPtr) => bytes.bytesFromList(outPtr, listPtr),
    json_decode_value: (outPtr, decoderPtr, valuePtr) =>
      json.jsonDecodeRun(outPtr, decoderPtr, valuePtr),
    json_decode_string: (outPtr, decoderPtr, stringPtr) =>
      json.jsonDecodeRunString(outPtr, decoderPtr, stringPtr),
    json_decode_string_decoder: (outPtr) =>
      json.writeDecoderOut(outPtr, json.primDecoder("string")),
    json_decode_int_decoder: (outPtr) => json.writeDecoderOut(outPtr, json.primDecoder("int")),
    json_decode_float_decoder: (outPtr) => json.writeDecoderOut(outPtr, json.primDecoder("float")),
    json_decode_bool_decoder: (outPtr) => json.writeDecoderOut(outPtr, json.primDecoder("bool")),
    json_decode_value_decoder: (outPtr) => json.writeDecoderOut(outPtr, json.primDecoder("value")),
    json_decode_null: (outPtr, defaultPtr) =>
      json.writeDecoderOut(outPtr, { kind: json.DEC_NULL, defaultHandle: defaultPtr }),
    json_decode_nullable: (outPtr, decoderPtr) =>
      json.writeDecoderOut(outPtr, {
        kind: json.DEC_ONE_OF,
        decoders: [
          json.newDecoder({ kind: json.DEC_NULL, defaultHandle: 0 }),
          decoderPtr,
        ],
      }),
    json_decode_list: (outPtr, decoderPtr) =>
      json.writeDecoderOut(outPtr, { kind: json.DEC_LIST, decoder: decoderPtr }),
    json_decode_array: (outPtr, decoderPtr) =>
      json.writeDecoderOut(outPtr, { kind: json.DEC_ARRAY, decoder: decoderPtr }),
    json_decode_field: (outPtr, namePtr, decoderPtr) =>
      json.writeDecoderOut(outPtr, {
        kind: json.DEC_FIELD,
        field: stringValue(namePtr),
        decoder: decoderPtr,
      }),
    json_decode_index: (outPtr, idxPtr, decoderPtr) =>
      json.writeDecoderOut(outPtr, {
        kind: json.DEC_INDEX,
        index: intValue(idxPtr),
        decoder: decoderPtr,
      }),
    json_decode_at: (outPtr, pathPtr, decoderPtr) => {
      let current = decoderPtr;
      for (const segmentPtr of [...listItems(pathPtr)].reverse()) {
        const segment = stringValue(segmentPtr);
        const index = Number.parseInt(segment, 10);
        current = json.newDecoder(
          Number.isNaN(index)
            ? { kind: json.DEC_FIELD, field: segment, decoder: current }
            : { kind: json.DEC_INDEX, index, decoder: current }
        );
      }
      writeOut(outPtr, current);
      return RC_SUCCESS;
    },
    json_decode_key_value_pairs: (outPtr, decoderPtr) =>
      json.writeDecoderOut(outPtr, { kind: json.DEC_KEY_VALUE, decoder: decoderPtr }),
    json_decode_dict: (outPtr, decoderPtr) =>
      json.writeDecoderOut(outPtr, { kind: json.DEC_KEY_VALUE, decoder: decoderPtr }),
    json_decode_map: (outPtr, funcPtr, decoderPtr) =>
      json.writeDecoderOut(outPtr, {
        kind: json.DEC_MAP,
        func: funcPtr,
        decoders: [decoderPtr],
      }),
    json_decode_map2: (outPtr, funcPtr, d1, d2) =>
      json.writeDecoderOut(outPtr, { kind: json.DEC_MAP, func: funcPtr, decoders: [d1, d2] }),
    json_decode_map3: (outPtr, funcPtr, d1, d2, d3) =>
      json.writeDecoderOut(outPtr, {
        kind: json.DEC_MAP,
        func: funcPtr,
        decoders: [d1, d2, d3],
      }),
    json_decode_map4: (outPtr, funcPtr, d1, d2, d3, d4) =>
      json.writeDecoderOut(outPtr, {
        kind: json.DEC_MAP,
        func: funcPtr,
        decoders: [d1, d2, d3, d4],
      }),
    json_decode_map5: (outPtr, funcPtr, d1, d2, d3, d4, d5) =>
      json.writeDecoderOut(outPtr, {
        kind: json.DEC_MAP,
        func: funcPtr,
        decoders: [d1, d2, d3, d4, d5],
      }),
    json_decode_map6: (outPtr, funcPtr, d1, d2, d3, d4, d5, d6) =>
      json.writeDecoderOut(outPtr, {
        kind: json.DEC_MAP,
        func: funcPtr,
        decoders: [d1, d2, d3, d4, d5, d6],
      }),
    json_decode_map7: (outPtr, funcPtr, d1, d2, d3, d4, d5, d6, d7) =>
      json.writeDecoderOut(outPtr, {
        kind: json.DEC_MAP,
        func: funcPtr,
        decoders: [d1, d2, d3, d4, d5, d6, d7],
      }),
    json_decode_succeed: (outPtr, valuePtr) =>
      json.writeDecoderOut(outPtr, { kind: json.DEC_SUCCEED, msg: valuePtr }),
    json_decode_fail: (outPtr, msgPtr) =>
      json.writeDecoderOut(outPtr, { kind: json.DEC_FAIL, msg: msgPtr }),
    json_decode_and_then: (outPtr, funcPtr, decoderPtr) =>
      json.writeDecoderOut(outPtr, {
        kind: json.DEC_AND_THEN,
        callback: funcPtr,
        decoder: decoderPtr,
      }),
    json_decode_one_of: (outPtr, decodersPtr) =>
      json.writeDecoderOut(outPtr, {
        kind: json.DEC_ONE_OF,
        decoders: listItems(decodersPtr).map((item) => asHandle(item)),
      }),
    json_decode_maybe: (outPtr, decoderPtr) =>
      json.writeDecoderOut(outPtr, {
        kind: json.DEC_ONE_OF,
        decoders: [
          json.newDecoder({ kind: json.DEC_NULL, defaultHandle: 0 }),
          decoderPtr,
        ],
      }),
    json_decode_lazy: (outPtr, thunkPtr) => {
      const thunk = invokeClosure(thunkPtr, []);
      if (thunk.rc !== RC_SUCCESS) {
        writeOut(outPtr, 0);
        return thunk.rc;
      }
      writeOut(outPtr, asHandle(thunk.value));
      release(thunk.value);
      return RC_SUCCESS;
    },
    json_decode_error_to_string: (outPtr, errPtr) => {
      writeOut(outPtr, newStringHandle(json.decodeErrorToString(errPtr)));
      return RC_SUCCESS;
    },
    json_encode_string: (outPtr, stringPtr) => {
      writeOut(outPtr, json.newJsonValue(stringValue(stringPtr)));
      return RC_SUCCESS;
    },
    json_encode_int: (outPtr, intPtr) => {
      writeOut(outPtr, json.newJsonValue(intValue(intPtr)));
      return RC_SUCCESS;
    },
    json_encode_float: (outPtr, floatPtr) => {
      const payload = readHandle(floatPtr);
      const value =
        payload?.tag === TAG_FLOAT ? payload.value : payload?.tag === TAG_INT ? payload.value : 0;
      writeOut(outPtr, json.newJsonValue(value));
      return RC_SUCCESS;
    },
    json_encode_bool: (outPtr, boolPtr) => {
      writeOut(outPtr, json.newJsonValue(intValue(boolPtr) !== 0));
      return RC_SUCCESS;
    },
    json_encode_null: (outPtr) => {
      writeOut(outPtr, json.newJsonValue(null));
      return RC_SUCCESS;
    },
    json_encode_list: json.jsonEncodeListLike,
    json_encode_array: json.jsonEncodeListLike,
    json_encode_set: json.jsonEncodeListLike,
    json_encode_object: json.jsonEncodeFromPairs,
    json_encode_dict: (outPtr, keyFnPtr, valFnPtr, dictPtr) => {
      const pairs = [];
      for (const entryPtr of listItems(dictPtr)) {
        const entry = readHandle(entryPtr);
        if (entry?.tag !== TAG_TUPLE2) continue;
        const keyOut = invokeClosure(keyFnPtr, [entry.first]);
        if (keyOut.rc !== RC_SUCCESS) {
          writeOut(outPtr, 0);
          return keyOut.rc;
        }
        const valOut = invokeClosure(valFnPtr, [entry.second]);
        if (valOut.rc !== RC_SUCCESS) {
          release(keyOut.value);
          writeOut(outPtr, 0);
          return valOut.rc;
        }
        pairs.push(
          allocHandle({
            tag: TAG_TUPLE2,
            first: asHandle(keyOut.value),
            second: asHandle(valOut.value),
          })
        );
        release(keyOut.value);
        release(valOut.value);
      }
      return json.jsonEncodeFromPairs(outPtr, newList(pairs));
    },
    json_encode_encode: (outPtr, indentPtr, valuePtr) => {
      const indent = intValue(indentPtr);
      const text = JSON.stringify(json.unwrapJsonValue(valuePtr), null, indent);
      writeOut(outPtr, newStringHandle(text));
      return RC_SUCCESS;
    },
    port_outgoing: (outPtr, portNamePtr, payloadPtr) => {
      const portName = stringValue(portNamePtr);
      outgoingPortQueue.push({ port: portName, payload: payloadPtr | 0 });
      writeOut(outPtr, cmdNoneHandle());
      return RC_SUCCESS;
    },
    cmd_batch: (outPtr, commandsPtr) => {
      const payload = readHandle(commandsPtr);
      if (cmdCellIsNone(commandsPtr)) {
        writeOut(outPtr, newIntHandle(0));
        return RC_SUCCESS;
      }
      if (payload?.tag === TAG_CMD) {
        writeOut(outPtr, commandsPtr);
        retain(null, commandsPtr);
        return RC_SUCCESS;
      }
      writeOut(outPtr, platformManagerBatch(commandsPtr));
      return RC_SUCCESS;
    },
    cmd_map: (outPtr, fnPtr, cmdPtr) => {
      const cmdPayload = readHandle(cmdPtr);
      if (cmdPayload?.tag === TAG_CMD) {
        writeOut(outPtr, cmdPtr);
        retain(null, cmdPtr);
        return RC_SUCCESS;
      }
      writeOut(outPtr, platformManagerMap(fnPtr, cmdPtr));
      return RC_SUCCESS;
    },
    sub_batch: (outPtr, subsPtr) => {
      if (listAllTag(subsPtr, TAG_SUB)) {
        writeOut(outPtr, subsPtr);
        retain(null, subsPtr);
        return RC_SUCCESS;
      }
      writeOut(outPtr, platformManagerBatch(subsPtr));
      return RC_SUCCESS;
    },
    sub_map: (outPtr, fnPtr, subPtr) => {
      const subPayload = readHandle(subPtr);
      if (subPayload?.tag === TAG_SUB) {
        writeOut(outPtr, subPtr);
        retain(null, subPtr);
        return RC_SUCCESS;
      }
      writeOut(outPtr, platformManagerMap(fnPtr, subPtr));
      return RC_SUCCESS;
    },
    port_incoming_sub: (outPtr, portNamePtr, callbackPtr) => {
      writeOut(outPtr, platformManagerPort(portNamePtr, callbackPtr));
      return RC_SUCCESS;
    },
    forward_ref_set: (refKey, valuePtr) => {
      const key = refKey | 0;
      const next = valuePtr | 0;
      const prev = forwardRefs.get(key);
      forwardRefs.set(key, next);
      if (prev && handles.has(prev) && prev !== next) {
        releaseUnlessReachable(prev, 0);
      }
      return RC_SUCCESS;
    },
    forward_ref_load: (outPtr, refKey) => {
      writeOut(outPtr, getForwardRefValue(refKey));
      return RC_SUCCESS;
    },
    forward_ref_capture: (outPtr, refKey) => {
      writeOut(outPtr, allocHandle({ tag: TAG_FORWARD_REF, refKey: refKey | 0 }));
      return RC_SUCCESS;
    },
    forward_ref_load_captured: (outPtr, refKey) => {
      writeOut(outPtr, getForwardRefValue(refKey));
      return RC_SUCCESS;
    },
  };

  const buildImport = (name) => {
    const impl = implementations[name];
    if (impl) return (...args) => impl(...args);
    return (...args) => {
      console.warn(`[elmc-wasm-runtime] unimplemented import ${name}`, args);
      const outPtr = args[0] | 0;
      if (outPtr) writeOut(outPtr, 0);
      return RC_ERR_UNIMPLEMENTED;
    };
  };

  return {
    setMemory,
    setClosureInvoker,
    setImmortalStrings,
    pushCallRoots,
    popCallRoots,
    buildImport,
    reachCacheStats: () => ({ hits: reachCacheHits, misses: reachCacheMisses }),
    unboxInt,
    checkBalanced,
    debugRcState,
    readHandle,
    writeOut,
    inspectVdom,
    forceLazyHtml: (lazyPtr, argPtrs) => forceLazyHtml(lazyPtr, argPtrs),
    vdomInnerText,
    mountVdomToApp,
    isBrowserProgram,
    bootBrowserProgram,
    mountViewHandle,
    drainOutgoingPorts,
    sendIncomingPort,
    deliverIncomingPort: (portName, payload) => deliverIncomingPortFn?.(portName, payload),
    dispatchPlatformMsg: (msgPtr) => dispatchPlatformMsg(msgPtr | 0),
    registerRouteBytes: (path, routeBytes) => routeBytesRuntime?.registerRoute(path, routeBytes),
    loadRouteBytesManifest: (url) => routeBytesRuntime?.loadManifest(url),
    setRouteBytesSiteRoot: (pageHtmlUrl) =>
      routeBytesRuntime?.setSiteRootFromPageHtml(pageHtmlUrl),
    urlFromLocation: (location) => urlRuntimeApi?.urlFromLocation(location) ?? 0,
    stringValue,
    newBytesFromUint8Array: (arr) =>
      bytes.newBytesHandle(new DataView(arr.buffer, arr.byteOffset, arr.byteLength)),
    bytesFromList: (list) => {
      const scratch = 8192;
      const listHandle = newList(list);
      const rc = bytes.bytesFromList(scratch, listHandle);
      release(listHandle);
      if (rc !== RC_SUCCESS) return 0;
      return view().getUint32(scratch, true);
    },
  };
}
