/**
 * Elm RC runtime for elmc WASM modules (Phase 1 execution harness).
 *
 * Imports follow the wasm ABI: (out_ptr, ...args) -> RC i32, writing result
 * handles into linear memory at out_ptr.
 */

import { createJsonRuntime } from "./json_runtime.js";

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

const HTML_KIND_TEXT = 1;
const HTML_KIND_NODE = 2;
const HTML_KIND_MAP = 3;
const HTML_KIND_ATTR = 4;
const HTML_KIND_STYLE = 5;
const HTML_KIND_CMD_NONE = 0;

const BROWSER_KIND_APPLICATION = 1;
const BROWSER_KIND_LOAD = 2;
const BROWSER_KIND_PUSH_URL = 3;
const BROWSER_KIND_REPLACE_URL = 4;
const BROWSER_KIND_SET_VIEWPORT = 5;
const BROWSER_KIND_ELEMENT = 6;
const BROWSER_KIND_DOCUMENT = 7;

export function createRcRuntime({ immortalStrings = {} } = {}) {
  let memory = null;
  let nextHandle = 2;
  const handles = new Map();
  const orderHandles = new Map();
  let retainCount = 0;
  let invokeClosureExport = null;
  let literalStrings = { ...immortalStrings };

  const UNIT_HANDLE = 1;
  handles.set(UNIT_HANDLE, { tag: TAG_INT, value: 0, immortal: true });

  const setClosureInvoker = (fn) => {
    invokeClosureExport = fn;
  };

  const setImmortalStrings = (table) => {
    literalStrings = { ...table };
  };

  const setMemory = (mem) => {
    memory = mem;
  };

  const view = () => new DataView(memory.buffer);

  const allocHandle = (payload) => {
    const handle = nextHandle++;
    handles.set(handle, payload);
    return handle;
  };

  const writeOut = (outPtr, handle) => {
    if (outPtr) view().setUint32(outPtr, handle, true);
  };

  const readHandle = (ptr) => (ptr ? handles.get(ptr) : null);

  const intValue = (ptr) => {
    if (!ptr) return 0;
    const payload = handles.get(ptr);
    return payload?.tag === TAG_INT ? payload.value | 0 : ptr | 0;
  };

  const newIntHandle = (value) => allocHandle({ tag: TAG_INT, value: value | 0 });

  const unit = (outPtr) => {
    writeOut(outPtr, UNIT_HANDLE);
    return RC_SUCCESS;
  };

  let browserProgram = null;

  const newBrowserProgram = (implPtr) => {
    browserProgram = { impl: implPtr | 0 };
    return allocHandle({ tag: TAG_BROWSER_PROGRAM, impl: implPtr | 0 });
  };

  const recordField = (recordPtr, index) => {
    const fields = readHandle(recordPtr)?.fields ?? [];
    return fields[index] ?? 0;
  };

  const tupleFirst = (tuplePtr) => readHandle(tuplePtr)?.first ?? 0;

  const mountViewHandle = (viewPtr) => {
    const payload = readHandle(viewPtr);
    if (payload?.tag === TAG_RECORD && (payload.fields?.length ?? 0) >= 2) {
      const titlePtr = payload.fields[0];
      const bodyPtr = payload.fields[1];
      if (typeof document !== "undefined") {
        const title = stringValue(titlePtr);
        if (title) document.title = title;
      }
      const root = ensureAppRoot();
      if (root) {
        root.replaceChildren();
        const wrapper = typeof document !== "undefined" ? document.createElement("div") : null;
        for (const child of listItems(bodyPtr)) {
          const dom = vdomToDom(asHandle(child));
          if (dom && wrapper) wrapper.appendChild(dom);
        }
        if (wrapper) root.appendChild(wrapper);
      }
      return RC_SUCCESS;
    }

    mountVdomToApp(viewPtr);
    return RC_SUCCESS;
  };

  const bootBrowserProgram = (programPtr, opts = {}) => {
    const program = readHandle(programPtr);
    if (program?.tag !== TAG_BROWSER_PROGRAM) {
      return { rc: RC_ERR_UNIMPLEMENTED, value: 0, innerText: "", stage: "program" };
    }

    const implPtr = program.impl | 0;
    const impl = readHandle(implPtr);
    if (impl?.tag !== TAG_RECORD) {
      return { rc: RC_ERR_UNIMPLEMENTED, value: 0, innerText: "", stage: "impl" };
    }

    const fieldCount = impl.fields?.length ?? 0;
    const initFn = recordField(implPtr, 0);
    const viewFn = recordField(implPtr, 1);
    const flags = opts.flags ?? 0;
    const url = opts.url ?? 0;
    const key = opts.key ?? 0;

    const initArgs = fieldCount >= 6 ? [flags, url, key] : [flags];
    const initResult = invokeClosure(initFn, initArgs);
    if (initResult.rc !== RC_SUCCESS) {
      return { rc: initResult.rc, value: 0, innerText: "", stage: "init" };
    }

    const initPayload = readHandle(initResult.value);
    const modelPtr =
      initPayload?.tag === TAG_TUPLE2 ? initPayload.first | 0 : initResult.value | 0;

    const viewResult = invokeClosure(viewFn, [modelPtr]);
    if (viewResult.rc !== RC_SUCCESS) {
      return { rc: viewResult.rc, value: 0, innerText: "", stage: "view" };
    }

    mountViewHandle(viewResult.value);
    const innerText = vdomInnerTextFromView(viewResult.value);
    return { rc: RC_SUCCESS, value: viewResult.value, innerText, modelPtr, stage: "ok" };
  };

  const vdomInnerTextFromView = (viewPtr) => {
    const payload = readHandle(viewPtr);
    if (payload?.tag === TAG_RECORD && (payload.fields?.length ?? 0) >= 2) {
      return listItems(payload.fields[1])
        .map((child) => vdomInnerText(asHandle(child)))
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
    if (payload?.tag === TAG_INT && payload.value !== ptr) {
      return ptr | 0;
    }
    return intValue(ptr);
  };

  const retain = (outPtr, handlePtr) => {
    const handle = handlePtr ?? outPtr;
    if (!outPtr && handle && handles.has(handle)) retainCount += 1;

    if (outPtr) {
      if (!handles.has(handlePtr)) {
        writeOut(outPtr, newIntHandle(wasmScalarArg(handlePtr)));
      } else {
        const payload = handles.get(handlePtr);
        if (payload?.tag === TAG_INT) {
          writeOut(outPtr, newIntHandle(payload.value));
        } else if (payload?.tag === TAG_MAYBE) {
          writeOut(outPtr, payload.value != null ? payload.value : handlePtr);
        } else if (payload?.tag === TAG_RESULT) {
          writeOut(outPtr, payload.value != null ? payload.value : handlePtr);
        } else {
          writeOut(outPtr, handlePtr);
        }
      }
    }

    return RC_SUCCESS;
  };

  const release = (ptr) => {
    if (!ptr || !handles.has(ptr)) {
      return RC_SUCCESS;
    }

    const payload = handles.get(ptr);

    if (payload?.immortal) {
      return RC_SUCCESS;
    }

    if (payload?.tag === TAG_MAYBE && payload.value && handles.has(payload.value)) {
      release(payload.value);
    }

    if (payload?.tag === TAG_RESULT && payload.value && handles.has(payload.value)) {
      release(payload.value);
    }

    if (payload?.tag === TAG_LIST) {
      for (const item of payload.items ?? []) {
        if (handles.has(item)) release(item);
      }
    }

    if (payload?.tag === TAG_TUPLE2) {
      if (payload.first && handles.has(payload.first)) release(payload.first);
      if (payload.second && handles.has(payload.second)) release(payload.second);
    }

    if (payload?.tag === TAG_RECORD) {
      for (const field of payload.fields ?? []) {
        if (field && handles.has(field)) release(field);
      }
    }

    if (payload?.tag === TAG_VDOM && payload.kind === "node") {
      for (const child of payload.children ?? []) {
        if (child && handles.has(child)) release(child);
      }
    }

    if (payload?.tag === TAG_VDOM && payload.kind === "attr") {
      // leaf attr payload
    }

    handles.delete(ptr);
    retainCount = Math.max(0, retainCount - 1);
    return RC_SUCCESS;
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

  const newVdomAttr = (name, value) =>
    allocHandle({ tag: TAG_VDOM, kind: "attr", name: String(name), value: String(value) });

  const vdomAttrs = (attrs) =>
    (attrs ?? [])
      .map((entry) => {
        if (!entry || typeof entry !== "object") return null;
        if (entry.name != null && entry.value != null) return { name: entry.name, value: entry.value };
        return null;
      })
      .filter(Boolean);

  const attrsFromList = (listPtr) =>
    listItems(listPtr)
      .map((item) => {
        const payload = readHandle(asHandle(item));
        if (payload?.tag === TAG_VDOM && payload.kind === "attr") {
          return { name: payload.name, value: payload.value };
        }
        return null;
      })
      .filter(Boolean);

  const newVdomText = (text) => allocHandle({ tag: TAG_VDOM, kind: "text", text: String(text) });

  const newVdomNode = (tagName, attrs, children) =>
    allocHandle({
      tag: TAG_VDOM,
      kind: "node",
      tagName: String(tagName),
      attrs: attrs ?? [],
      children: children ?? [],
    });

  const inspectVdom = (ptr) => {
    const payload = readHandle(ptr);
    if (!payload || payload.tag !== TAG_VDOM) return null;
    if (payload.kind === "text") return { kind: "text", text: payload.text };
    if (payload.kind === "node") {
      return {
        kind: "node",
        tagName: payload.tagName,
        childCount: (payload.children ?? []).length,
        innerText: vdomInnerText(ptr),
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

  const ensureAppRoot = () => {
    let root = document.getElementById("app");
    if (!root && typeof document !== "undefined") {
      root = document.createElement("div");
      root.id = "app";
      document.body.appendChild(root);
    }
    return root;
  };

  const vdomToDom = (ptr) => {
    const payload = readHandle(ptr);
    if (!payload || payload.tag !== TAG_VDOM) {
      return typeof document !== "undefined" ? document.createTextNode("") : null;
    }

    if (payload.kind === "text") {
      return typeof document !== "undefined" ? document.createTextNode(payload.text) : null;
    }

    if (payload.kind === "node" && typeof document !== "undefined") {
      const el = document.createElement(payload.tagName || "div");
      let styleText = "";
      for (const attr of vdomAttrs(payload.attrs)) {
        if (attr.name === "style") {
          styleText += attr.value;
        } else if (attr.name === "class") {
          el.className = attr.value;
        } else {
          el.setAttribute(attr.name, attr.value);
        }
      }
      if (styleText) el.setAttribute("style", styleText);
      for (const child of payload.children ?? []) {
        const childDom = vdomToDom(child);
        if (childDom) el.appendChild(childDom);
      }
      return el;
    }

    return typeof document !== "undefined" ? document.createTextNode("") : null;
  };

  const mountVdomToApp = (ptr) => {
    if (typeof document === "undefined") return;
    const root = ensureAppRoot();
    if (!root) return;
    root.replaceChildren();
    const dom = vdomToDom(ptr);
    if (dom) root.appendChild(dom);
  };

  const listItems = (ptr) => readHandle(ptr)?.items ?? [];

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
    const payload = readHandle(ptr);
    if (payload?.tag === TAG_VDOM) return cloneVdom(ptr);
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

  const listReverse = (outPtr, listPtr) => writeList(outPtr, [...listItems(listPtr)].reverse());

  const listAppend = (outPtr, leftPtr, rightPtr) =>
    writeList(outPtr, [...listItems(leftPtr), ...listItems(rightPtr)]);

  const listConcat = (outPtr, listsPtr) => {
    const items = [];
    for (const innerHandle of listItems(listsPtr)) {
      items.push(...listItems(innerHandle));
    }
    return writeList(outPtr, items);
  };

  const listMember = (outPtr, valuePtr, listPtr) => {
    const value = intValue(valuePtr);
    const found = listItems(listPtr).some((item) => item === value);
    return newInt(outPtr, found ? 1 : 0);
  };

  const listIsEmpty = (outPtr, listPtr) => newInt(outPtr, listItems(listPtr).length === 0 ? 1 : 0);

  const listHead = (outPtr, listPtr) => {
    const items = listItems(listPtr);
    if (items.length === 0) return maybeNothing(outPtr);
    return maybeJustOwn(outPtr, newIntHandle(items[0]));
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
    const start = intValue(startPtr);
    const end = intValue(endPtr);
    const items = [];
    for (let i = start; i < end; i++) items.push(i);
    return writeList(outPtr, items);
  };

  const listRepeat = (outPtr, valuePtr, countPtr) => {
    const value = intValue(valuePtr);
    const count = intValue(countPtr);
    return writeList(outPtr, Array.from({ length: count }, () => value));
  };

  const listSingleton = (outPtr, valuePtr) => writeList(outPtr, [intValue(valuePtr)]);

  const listCons = (outPtr, headPtr, tailPtr) =>
    writeList(outPtr, [intValue(headPtr), ...listItems(tailPtr)]);

  const listMaximum = (outPtr, listPtr) => {
    const items = listItems(listPtr);
    return newInt(outPtr, items.length === 0 ? 0 : Math.max(...items));
  };

  const listMinimum = (outPtr, listPtr) => {
    const items = listItems(listPtr);
    return newInt(outPtr, items.length === 0 ? 0 : Math.min(...items));
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
    const payload = readHandle(ptr);
    return payload?.tag !== TAG_MAYBE || payload.value == null;
  };

  const maybeJustInt = (ptr) => {
    const payload = readHandle(ptr);
    if (payload?.tag === TAG_MAYBE && payload.value != null) {
      return intValue(payload.value);
    }
    return null;
  };

  const listSortWith = (outPtr, cmpClosurePtr, listPtr) => {
    const items = [...listItems(listPtr)];
    items.sort((left, right) => {
      const argA = newIntHandle(left);
      const argB = newIntHandle(right);
      const { rc, value } = invokeClosure(cmpClosurePtr, [argA, argB]);
      release(argA);
      release(argB);
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
      const arg = newIntHandle(item);
      const { rc, value } = invokeClosure(keyClosurePtr, [arg]);
      release(arg);
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
      const arg = newIntHandle(item);
      const { rc, value } = invokeClosure(closurePtr, [arg, accHandle]);
      release(arg);
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
      const arg = newIntHandle(items[i]);
      const { rc, value } = invokeClosure(closurePtr, [arg, accHandle]);
      release(arg);
      if (rc !== RC_SUCCESS) return rc;
      if (accHandle) release(accHandle);
      accHandle = value;
    }

    writeOut(outPtr, accHandle);
    return RC_SUCCESS;
  };

  const listAny = (outPtr, predClosurePtr, listPtr) => {
    for (const item of listItems(listPtr)) {
      const arg = newIntHandle(item);
      const { rc, value } = invokeClosure(predClosurePtr, [arg]);
      release(arg);
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
      const arg = newIntHandle(item);
      const { rc, value } = invokeClosure(predClosurePtr, [arg]);
      release(arg);
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
      const arg = newIntHandle(item);
      const { rc, value } = invokeClosure(closurePtr, [arg]);
      release(arg);
      if (rc !== RC_SUCCESS) return rc;

      if (!isMaybeNothing(value)) {
        const mapped = maybeJustInt(value);
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

  const maybeJustOwn = (outPtr, payloadHandle) => {
    const owned = handles.has(payloadHandle)
      ? payloadHandle
      : newIntHandle(intValue(asHandle(payloadHandle)));
    writeOut(outPtr, allocHandle({ tag: TAG_MAYBE, value: owned }));
    return RC_SUCCESS;
  };

  const maybeIsNothing = (outPtr, maybePtr) => {
    const payload = readHandle(maybePtr);
    const isNothing = payload?.tag !== TAG_MAYBE || payload.value == null;
    return newInt(outPtr, isNothing ? 1 : 0);
  };

  const maybeWithDefault = (outPtr, defaultPtr, maybePtr) => {
    const payload = readHandle(maybePtr);
    if (payload?.tag === TAG_MAYBE && payload.value != null) {
      return newInt(outPtr, intValue(payload.value));
    }

    return newInt(outPtr, intValue(defaultPtr));
  };

  const maybeMap = (outPtr, closurePtr, maybePtr) => {
    if (isMaybeNothing(maybePtr)) return maybeNothing(outPtr);
    const justValue = readHandle(maybePtr).value;
    const { rc, value } = invokeClosure(closurePtr, [asHandle(justValue)]);
    if (rc !== RC_SUCCESS) return rc;
    const mapRc = maybeJustOwn(outPtr, value);
    release(value);
    return mapRc;
  };

  const maybeMap2 = (outPtr, closurePtr, aPtr, bPtr) => {
    if (isMaybeNothing(aPtr) || isMaybeNothing(bPtr)) return maybeNothing(outPtr);
    const aValue = readHandle(aPtr).value;
    const bValue = readHandle(bPtr).value;
    const { rc, value } = invokeClosure(closurePtr, [asHandle(aValue), asHandle(bValue)]);
    if (rc !== RC_SUCCESS) return rc;
    const mapRc = maybeJustOwn(outPtr, value);
    release(value);
    return mapRc;
  };

  const maybeAndThen = (outPtr, closurePtr, maybePtr) => {
    if (isMaybeNothing(maybePtr)) return maybeNothing(outPtr);
    const justValue = readHandle(maybePtr).value;
    const { rc, value } = invokeClosure(closurePtr, [asHandle(justValue)]);
    if (rc !== RC_SUCCESS) return rc;
    writeOut(outPtr, asHandle(value));
    return RC_SUCCESS;
  };

  const tupleElements = (ptr) => {
    const payload = readHandle(ptr);
    if (!payload) return null;

    if (payload.tag === TAG_TUPLE2) {
      return { first: payload.first, second: payload.second, boxed: true };
    }

    if (payload.tag === TAG_LIST && payload.items.length >= 2) {
      return { first: payload.items[0], second: payload.items[1], boxed: false };
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
    writeOut(outPtr, internOrder(compareInts(intValue(leftPtr), intValue(rightPtr))));
    return RC_SUCCESS;
  };

  const basicsNot = (outPtr, valuePtr) => newInt(outPtr, intValue(valuePtr) === 0 ? 1 : 0);

  const tuple2Ints = (outPtr, aPtr, bPtr) => {
    writeOut(
      outPtr,
      allocHandle({ tag: TAG_LIST, items: [intValue(aPtr), intValue(bPtr)] })
    );
    return RC_SUCCESS;
  };

  const tuple2 = (outPtr, firstPtr, secondPtr) => {
    writeOut(
      outPtr,
      allocHandle({ tag: TAG_TUPLE2, first: firstPtr, second: secondPtr })
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
      const fieldPayload = readHandle(field);
      if (fieldPayload?.tag === TAG_STRING) {
        writeOut(outPtr, newStringHandle(fieldPayload.value));
      } else if (fieldPayload?.tag === TAG_CHAR) {
        writeOut(outPtr, newCharHandle(fieldPayload.value));
      } else {
        writeOut(outPtr, field);
      }
      return RC_SUCCESS;
    }

    const items = listItems(subject);
    return newInt(outPtr, items[index] ?? 0);
  };

  const stringValue = (ptr) => {
    if (!ptr) return "";
    const payload = handles.get(ptr);
    if (payload?.tag === TAG_STRING) return payload.value;
    return "";
  };

  const newStringHandle = (text) => allocHandle({ tag: TAG_STRING, value: String(text) });

  const resultPayload = (ptr) => {
    const payload = readHandle(ptr);
    return payload?.tag === TAG_RESULT ? payload : null;
  };

  const resultOkOwn = (outPtr, valueHandle) => {
    writeOut(outPtr, allocHandle({ tag: TAG_RESULT, isOk: true, value: valueHandle }));
    return RC_SUCCESS;
  };

  const resultErrOwn = (outPtr, valueHandle) => {
    writeOut(outPtr, allocHandle({ tag: TAG_RESULT, isOk: false, value: valueHandle }));
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

  const floatFromHandle = (ptr) => {
    const payload = readHandle(ptr);
    if (payload?.tag === TAG_FLOAT) return payload.value;
    return wasmScalarArg(ptr);
  };

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
      release(arg);
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
      release(arg);
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
    newInt(outPtr, Math.max(wasmScalarArg(aPtr), wasmScalarArg(bPtr)));
  const basicsMin = (outPtr, aPtr, bPtr) =>
    newInt(outPtr, Math.min(wasmScalarArg(aPtr), wasmScalarArg(bPtr)));
  const basicsClamp = (outPtr, lowPtr, highPtr, nPtr) =>
    newInt(
      outPtr,
      Math.max(wasmScalarArg(lowPtr), Math.min(wasmScalarArg(highPtr), wasmScalarArg(nPtr)))
    );
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

  const normalizeFieldHandle = (ptr) =>
    handles.has(ptr) ? ptr : newIntHandle(wasmScalarArg(ptr));

  const recordNew = (outPtr, ...fieldPtrs) => {
    const fields = fieldPtrs.map((ptr) => normalizeFieldHandle(ptr));
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
    }
    return RC_SUCCESS;
  };

  const recordUpdate = (outPtr, recordPtr, valuePtr, indexPtr) => {
    const index = wasmScalarArg(indexPtr);
    const fields = [...(readHandle(recordPtr)?.fields ?? [])];
    if (index >= 0 && index < fields.length) {
      fields[index] = normalizeFieldHandle(valuePtr);
    }
    writeOut(outPtr, allocHandle({ tag: TAG_RECORD, fields }));
    return RC_SUCCESS;
  };

  const listNthMaybe = (outPtr, listPtr, indexPtr) => {
    const index = wasmScalarArg(indexPtr);
    const items = listItems(listPtr);
    if (index < 0 || index >= items.length) return maybeNothing(outPtr);
    return maybeJustOwn(outPtr, asHandle(items[index]));
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

  const valuesEqual = (leftPtr, rightPtr) => {
    const left = readHandle(leftPtr);
    const right = readHandle(rightPtr);
    if (left?.tag === TAG_STRING && right?.tag === TAG_STRING) return left.value === right.value;
    return intValue(leftPtr) === intValue(rightPtr);
  };

  const compareValues = (leftPtr, rightPtr) => {
    const left = readHandle(leftPtr);
    const right = readHandle(rightPtr);
    if (left?.tag === TAG_STRING && right?.tag === TAG_STRING) {
      return left.value < right.value ? -1 : left.value > right.value ? 1 : 0;
    }
    return compareInts(intValue(leftPtr), intValue(rightPtr));
  };

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
    const text = literalStrings[String(literalId)] ?? "";
    writeOut(outPtr, newStringHandle(text));
    return RC_SUCCESS;
  };

  const makeClosure = (outPtr, fnIndex, arity, ...captures) => {
    writeOut(
      outPtr,
      allocHandle({
        tag: TAG_CLOSURE,
        fnIndex: fnIndex | 0,
        arity: arity | 0,
        captures: captures.filter((handle) => handle !== 0),
      })
    );
    return RC_SUCCESS;
  };

  const invokeClosure = (closurePtr, callArgs) => {
    const payload = readHandle(closurePtr);
    if (payload?.tag !== TAG_CLOSURE || typeof invokeClosureExport !== "function") {
      return { rc: RC_SUCCESS, value: newIntHandle(0) };
    }

    const { rc, value } = invokeClosureExport(payload.fnIndex, payload.captures, callArgs);
    if (rc !== RC_SUCCESS) return { rc, value: 0 };
    return { rc, value: normalizeClosureValue(value) };
  };

  const normalizeClosureValue = (value) => {
    if (!value) return newIntHandle(0);
    if (handles.has(value)) return value;
    return newIntHandle(intValue(value));
  };

  const callClosure = (outPtr, closurePtr, ...callArgs) => {
    const { rc, value } = invokeClosure(closurePtr, callArgs);
    if (rc !== RC_SUCCESS) return rc;
    writeOut(outPtr, value);
    return RC_SUCCESS;
  };

  const mapListWithClosure = (outPtr, closurePtr, listPtr) => {
    const results = [];

    for (const item of listItems(listPtr)) {
      const arg = newIntHandle(item);
      const { rc, value } = invokeClosure(closurePtr, [arg]);
      release(arg);
      if (rc !== RC_SUCCESS) return rc;
      results.push(intValue(value));
      release(value);
    }

    return writeList(outPtr, results);
  };

  const filterListWithClosure = (outPtr, closurePtr, listPtr) => {
    const kept = [];

    for (const item of listItems(listPtr)) {
      const arg = newIntHandle(item);
      const { rc, value } = invokeClosure(closurePtr, [arg]);
      release(arg);
      if (rc !== RC_SUCCESS) return rc;
      if (intValue(value) !== 0) kept.push(item);
      release(value);
    }

    return writeList(outPtr, kept);
  };

  const unboxInt = (handle) => intValue(handle);

  const checkBalanced = () => retainCount === 0 && handles.size === 0;

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
  });

  const implementations = {
    retain,
    release,
    release_array_lifo: releaseArrayLifo,
    as_int: intValue,
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
    task_succeed: taskSucceed,
    task_fail: taskFail,
    process_spawn: processSpawn,
    process_sleep: processSleep,
    process_kill: processKill,
    record_new: recordNew,
    record_get: recordGet,
    record_update: recordUpdate,
    list_nth_maybe: listNthMaybe,
    list_nth_int_default: listNthIntDefault,
    list_replace_nth_int: listReplaceNthInt,
    list_slice_int: listSliceInt,
    int_list_head_int: intListHeadInt,
    int_list_tail: intListTail,
    tuple2_ints: tuple2Ints,
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
    string_is_empty: stringIsEmpty,
    string_reverse: stringReverse,
    string_repeat: stringRepeat,
    string_replace: stringReplace,
    string_from_int_value: stringFromIntValue,
    string_from_int: stringFromIntValue,
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
    list_map2: (outPtr, closurePtr, aPtr, bPtr) => {
      const a = listItems(aPtr);
      const b = listItems(bPtr);
      const results = [];

      for (let i = 0; i < a.length; i++) {
        const argA = newIntHandle(a[i] ?? 0);
        const argB = newIntHandle(b[i] ?? 0);
        const { rc, value } = invokeClosure(closurePtr, [argA, argB]);
        release(argA);
        release(argB);
        if (rc !== RC_SUCCESS) return rc;
        results.push(intValue(value));
        release(value);
      }

      return writeList(outPtr, results);
    },
    list_map3: (outPtr, closurePtr, aPtr, bPtr, cPtr) => {
      const a = listItems(aPtr);
      const b = listItems(bPtr);
      const c = listItems(cPtr);
      const results = [];

      for (let i = 0; i < a.length; i++) {
        const args = [
          newIntHandle(a[i] ?? 0),
          newIntHandle(b[i] ?? 0),
          newIntHandle(c[i] ?? 0),
        ];
        const { rc, value } = invokeClosure(closurePtr, args);
        for (const arg of args) release(arg);
        if (rc !== RC_SUCCESS) return rc;
        results.push(intValue(value));
        release(value);
      }

      return writeList(outPtr, results);
    },
    list_map4: (outPtr, closurePtr, aPtr, bPtr, cPtr, dPtr) => {
      const lists = [listItems(aPtr), listItems(bPtr), listItems(cPtr), listItems(dPtr)];
      const results = [];

      for (let i = 0; i < lists[0].length; i++) {
        const args = lists.map((items) => newIntHandle(items[i] ?? 0));
        const { rc, value } = invokeClosure(closurePtr, args);
        for (const arg of args) release(arg);
        if (rc !== RC_SUCCESS) return rc;
        results.push(intValue(value));
        release(value);
      }

      return writeList(outPtr, results);
    },
    list_map5: (outPtr, closurePtr, aPtr, bPtr, cPtr, dPtr, ePtr) => {
      const lists = [
        listItems(aPtr),
        listItems(bPtr),
        listItems(cPtr),
        listItems(dPtr),
        listItems(ePtr),
      ];
      const results = [];

      for (let i = 0; i < lists[0].length; i++) {
        const args = lists.map((items) => newIntHandle(items[i] ?? 0));
        const { rc, value } = invokeClosure(closurePtr, args);
        for (const arg of args) release(arg);
        if (rc !== RC_SUCCESS) return rc;
        results.push(intValue(value));
        release(value);
      }

      return writeList(outPtr, results);
    },
    list_filter: filterListWithClosure,
    list_filter_map: filterMapListWithClosure,
    list_indexed_map: (outPtr, closurePtr, listPtr) => {
      const results = [];

      for (let index = 0; index < listItems(listPtr).length; index++) {
        const item = listItems(listPtr)[index];
        const args = [newIntHandle(index), newIntHandle(item)];
        const { rc, value } = invokeClosure(closurePtr, args);
        release(args[0]);
        release(args[1]);
        if (rc !== RC_SUCCESS) return rc;
        results.push(intValue(value));
        release(value);
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

      if (kind === HTML_KIND_STYLE) {
        const propPtr = params[0] | 0;
        const valPtr = params[1] | 0;
        const handle = newVdomAttr("style", `${stringValue(propPtr)}: ${stringValue(valPtr)};`);
        writeOut(outPtr, handle);
        return RC_SUCCESS;
      }

      if (kind === HTML_KIND_MAP) {
        const childPtr = params[1] | 0;
        writeOut(outPtr, cloneVdom(asHandle(childPtr)));
        return RC_SUCCESS;
      }

      if (kind === HTML_KIND_NODE) {
        const tagPtr = params[0] | 0;
        const attrsPtr = params[1] | 0;
        const childrenPtr = params[2] | 0;
        const attrs = attrsFromList(attrsPtr);
        const children = listItems(childrenPtr).map((item) => cloneVdom(asHandle(item)));
        const handle = newVdomNode(stringValue(tagPtr), attrs, children);
        writeOut(outPtr, handle);
        return RC_SUCCESS;
      }

      console.warn("[elmc-wasm-runtime] html_cmd unimplemented kind", kind, { params });
      writeOut(outPtr, 0);
      return RC_ERR_UNIMPLEMENTED;
    },
    browser_cmd: (outPtr, kindPtr, ...params) => {
      const kind = wasmScalarArg(kindPtr);

      if (kind === BROWSER_KIND_APPLICATION || kind === BROWSER_KIND_ELEMENT || kind === BROWSER_KIND_DOCUMENT) {
        const implPtr = params[0] | 0;
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
          const url = stringValue(urlPtr);
          if (kind === BROWSER_KIND_PUSH_URL) {
            window.history.pushState({}, "", url);
          } else {
            window.history.replaceState({}, "", url);
          }
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

      console.warn("[elmc-wasm-runtime] browser_cmd unimplemented kind", kind, { params });
      writeOut(outPtr, cmdNoneHandle());
      return RC_SUCCESS;
    },
    dom_sub: (outPtr, kindPtr, ...params) => {
      const kind = wasmScalarArg(kindPtr);
      if (kind === 0) {
        writeOut(outPtr, newIntHandle(0));
        return RC_SUCCESS;
      }
      console.warn("[elmc-wasm-runtime] dom_sub unimplemented", { kindPtr, params });
      writeOut(outPtr, 0);
      return RC_ERR_UNIMPLEMENTED;
    },
    json_cmd: (outPtr, kindPtr, ...params) => json.jsonCmd(outPtr, wasmScalarArg(kindPtr), ...params),
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
      writeOut(outPtr, newStringHandle(stringValue(errPtr)));
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
      console.warn("[elmc-wasm-runtime] port_outgoing unimplemented", { portName, payloadPtr });
      writeOut(outPtr, 0);
      return RC_ERR_UNIMPLEMENTED;
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
    buildImport,
    unboxInt,
    checkBalanced,
    readHandle,
    writeOut,
    inspectVdom,
    vdomInnerText,
    mountVdomToApp,
    isBrowserProgram,
    bootBrowserProgram,
    mountViewHandle,
  };
}
