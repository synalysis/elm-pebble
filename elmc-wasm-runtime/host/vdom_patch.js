/**
 * VirtualDom diff/patch for elmc WASM web host.
 */

export function createVdomPatchRuntime(deps) {
  const {
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
    applyLazyHtml,
    // VirtualDom "custom" node handlers, keyed by renderKey (e.g. "webgl").
    // Each entry is `{ render(model, facts) -> Node, diff(oldModel, newModel,
    // domNode) -> Node }`. `model` is a host-only JS object (not a handle
    // pointer) owned by the TAG_VDOM payload — see webgl_runtime.js. Shared
    // by reference with rc_runtime.js so handlers registered after this
    // runtime is constructed still apply.
    customNodeHandlers = {},
  } = deps;

  /** @type {WeakMap<Node, { vdomPtr: number, listeners: Array<{el: Element, type: string, fn: Function}> }>} */
  const domState = new WeakMap();

  const vdomKind = (ptr) => {
    const payload = readHandle(resolveHtml(ptr));
    if (!payload) return null;
    if (payload.tag === TAG_VDOM) return payload.kind ?? "node";
    if (payload.tag === TAG_RECORD) return "document";
    return null;
  };

  const vdomTag = (ptr) => {
    const p = readHandle(resolveHtml(ptr));
    if (p?.tag === TAG_VDOM) return p.tagName ?? p.ns ?? "div";
    return "div";
  };

  const vdomAttrs = (ptr) => {
    const p = readHandle(resolveHtml(ptr));
    if (p?.tag !== TAG_VDOM) return [];
    return p.attrs ?? [];
  };

  const vdomChildren = (ptr) => {
    const p = readHandle(resolveHtml(ptr));
    if (p?.tag === TAG_VDOM) return p.children ?? [];
    if (p?.tag === TAG_RECORD) {
      const fields = p.fields ?? [];
      if (fields.length >= 2) return listItems(fields[1]);
    }
    return [];
  };

  const vdomKeyedChildren = (ptr) => {
    const p = readHandle(resolveHtml(ptr));
    if (p?.tag === TAG_VDOM && Array.isArray(p.keyedChildren)) {
      return p.keyedChildren;
    }
    return null;
  };

  const vdomText = (ptr) => {
    const p = readHandle(resolveHtml(ptr));
    if (p?.tag === TAG_VDOM && p.kind === "text") return p.text ?? "";
    return null;
  };

  const vdomMapper = (ptr) => {
    const p = readHandle(resolveHtml(ptr));
    if (p?.tag === TAG_VDOM && p.kind === "map") return p.mapper | 0;
    return 0;
  };

  const vdomMapChild = (ptr) => {
    const p = readHandle(resolveHtml(ptr));
    if (p?.tag === TAG_VDOM && p.kind === "map") return p.child | 0;
    return 0;
  };

  const normalizeMappers = (mappers) => {
    if (Array.isArray(mappers)) return mappers.filter((m) => (m | 0) !== 0);
    const single = mappers | 0;
    return single ? [single] : [];
  };

  const pushMapper = (mappers, mapperPtr) => {
    const m = mapperPtr | 0;
    if (!m) return normalizeMappers(mappers);
    return [m, ...normalizeMappers(mappers)];
  };

  const vdomCustom = (ptr) => {
    const p = readHandle(resolveHtml(ptr));
    if (p?.tag !== TAG_VDOM || p.kind !== "custom") return null;
    // model is a host-side JS object (entities/options handles + cache), not a
    // handle pointer — never coerce with `| 0`.
    return { renderKey: p.renderKey, model: p.model, facts: p.facts ?? [] };
  };

  const clearListeners = (node) => {
    const state = domState.get(node);
    if (!state) return;
    for (const { el, type, fn } of state.listeners) {
      el.removeEventListener(type, fn);
    }
    state.listeners = [];
  };

  const createTextDom = (text) => {
    if (typeof document === "undefined") return null;
    return document.createTextNode(text);
  };

  const createElementDom = (tag, ns) => {
    if (typeof document === "undefined") return null;
    return ns ? document.createElementNS(ns, tag) : document.createElement(tag);
  };

  const applyAttrs = (el, attrs, mappers) => {
    if (!el || !attrs) return;
    const mapperChain = normalizeMappers(mappers);
    for (const attr of attrs) {
      if (!attr) continue;
      const name = attr.name ?? attr.key;
      const value = attr.value ?? "";
      if (attr.kind === "style") {
        const key = String(name || "");
        const val = String(value ?? "");
        if (key && el.style) {
          if (typeof el.style.setProperty === "function") {
            el.style.setProperty(key, val);
          } else {
            el.style[key] = val;
          }
        }
      } else if (name === "style" && typeof value === "string") {
        el.setAttribute("style", value);
      } else if (attr.kind === "property") {
        // A "property" fact is always a direct JS-property assignment (e.g.
        // canvas.width/height, input.value/checked) — never setAttribute.
        // Numeric IDL props (width/height) coerce a numeric string fine.
        el[attr.name] = attr.value;
      } else if (attr.kind === "event" && attachDomEvent) {
        const fn = attachDomEvent(el, attr, mapperChain);
        const state = domState.get(el) ?? { vdomPtr: 0, listeners: [] };
        state.listeners.push({ el, type: attr.event, fn });
        domState.set(el, state);
      } else if (name) {
        if (attr.ns && typeof el.setAttributeNS === "function") {
          el.setAttributeNS(attr.ns, name, value);
        } else {
          el.setAttribute(name, value);
        }
      }
    }
  };

  const mount = (parent, vdomPtr, mappers = []) => {
    const mapperChain = normalizeMappers(mappers);
    const resolved = resolveHtml(vdomPtr);
    const text = vdomText(resolved);
    if (text != null) {
      const node = createTextDom(text);
      if (node && parent) parent.appendChild(node);
      return node;
    }

    const kind = vdomKind(resolved);
    if (kind === "map") {
      // Descend into the mapped child while prepending this node's mapper so
      // nested Html.map composes (inner then outer).
      const child = vdomMapChild(resolved);
      return mount(parent, child || resolved, pushMapper(mapperChain, vdomMapper(resolved)));
    }

    if (kind === "lazy") {
      const forced = forceLazyHtml(resolved);
      if (forced.rc === 0 && forced.value) {
        return mount(parent, forced.value, mapperChain);
      }
      return null;
    }

    if (kind === "custom") {
      const custom = vdomCustom(resolved);
      const handler = custom && customNodeHandlers[custom.renderKey];
      const el = handler ? handler.render(custom.model, custom.facts) : null;
      if (!el) return null;
      applyAttrs(el, custom.facts, mapperChain);
      if (parent) parent.appendChild(el);
      domState.set(el, { vdomPtr: resolved | 0, listeners: [] });
      return el;
    }

    if (kind === "document") {
      const frag = typeof document !== "undefined" ? document.createDocumentFragment() : null;
      for (const child of vdomChildren(resolved)) {
        mount(frag, child, mapperChain);
      }
      if (frag && parent) parent.appendChild(frag);
      return frag;
    }

    const payload = readHandle(resolved);
    const tag = payload?.tagName ?? "div";
    const ns = payload?.namespace ?? payload?.ns ?? null;
    const el = createElementDom(tag, ns);
    if (!el) return null;

    // Record listeners in domState *during* applyAttrs. Overwriting
    // `{ listeners: [] }` after apply left the click handler untracked, so
    // the next patch stacked a second listener.
    domState.set(el, { vdomPtr: resolved | 0, listeners: [] });
    applyAttrs(el, vdomAttrs(resolved), mapperChain);

    const keyed = vdomKeyedChildren(resolved);
    if (keyed) {
      for (const { key, child } of keyed) {
        const childEl = mount(el, child, mapperChain);
        if (childEl && key != null) childEl.__vdomKey = String(key);
      }
    } else {
      for (const child of vdomChildren(resolved)) {
        mount(el, child, mapperChain);
      }
    }

    if (parent) parent.appendChild(el);
    const mounted = domState.get(el) ?? { listeners: [] };
    domState.set(el, { vdomPtr: resolved | 0, listeners: mounted.listeners ?? [] });
    return el;
  };

  const patch = (oldPtr, newPtr, domNode, mappers = []) => {
    const mapperChain = normalizeMappers(mappers);
    if (!domNode) {
      return mount(null, newPtr, mapperChain);
    }

    const oldResolved = oldPtr ? resolveHtml(oldPtr) : 0;
    const newResolved = resolveHtml(newPtr);

    const oldText = oldPtr ? vdomText(oldResolved) : null;
    const newText = vdomText(newResolved);
    if (newText != null) {
      if (oldText != null && domNode.nodeType === Node.TEXT_NODE) {
        if (domNode.textContent !== newText) domNode.textContent = newText;
        return domNode;
      }
      const replacement = createTextDom(newText);
      domNode.replaceWith(replacement);
      return replacement;
    }

    const newKind = vdomKind(newResolved);
    if (newKind === "map") {
      const child = vdomMapChild(newResolved);
      // Unwrap Html.map on the *old* side too. Leaving oldPtr as a map node made
      // custom/webgl patches see oldKind==="map" !== "custom", so they replaced the
      // canvas via render() instead of calling diff/drawGL — or skipped updates.
      const oldChild =
        oldPtr && vdomKind(oldResolved) === "map"
          ? vdomMapChild(oldResolved) || oldPtr
          : oldPtr;
      return patch(
        oldChild,
        child || newResolved,
        domNode,
        pushMapper(mapperChain, vdomMapper(newResolved))
      );
    }

    if (newKind === "lazy") {
      if (typeof applyLazyHtml === "function") {
        const step = applyLazyHtml(oldPtr, newPtr);
        if (step.reused) return domNode;
        if (step.newForced) {
          return patch(step.oldForced || 0, step.newForced, domNode, mapperChain);
        }
        return domNode;
      }
      const forced = forceLazyHtml(newResolved);
      if (forced.rc === 0 && forced.value) {
        return patch(oldPtr, forced.value, domNode, mapperChain);
      }
      return domNode;
    }

    if (newKind === "custom") {
      const newCustom = vdomCustom(newResolved);
      const handler = newCustom && customNodeHandlers[newCustom.renderKey];
      // Peel Html.map wrappers from the previous tree so we can reuse the canvas.
      let oldComparePtr = oldPtr;
      let oldCompareResolved = oldResolved;
      let oldKind = oldPtr ? vdomKind(oldResolved) : null;
      while (oldKind === "map" && oldComparePtr) {
        const unwrapped = vdomMapChild(oldCompareResolved);
        if (!unwrapped || unwrapped === oldComparePtr) break;
        oldComparePtr = unwrapped;
        oldCompareResolved = resolveHtml(oldComparePtr);
        oldKind = vdomKind(oldCompareResolved);
      }

      if (
        handler &&
        oldKind === "custom" &&
        vdomCustom(oldCompareResolved)?.renderKey === newCustom.renderKey &&
        domNode.nodeType === Node.ELEMENT_NODE
      ) {
        const oldCustom = vdomCustom(oldCompareResolved);
        const updated = handler.diff(oldCustom.model, newCustom.model, domNode) || domNode;
        clearListeners(updated);
        applyAttrs(updated, newCustom.facts, mapperChain);
        return updated;
      }

      clearListeners(domNode);
      const parent = domNode.parentNode;
      const fresh = handler ? handler.render(newCustom.model, newCustom.facts) : null;
      if (!fresh) return domNode;
      applyAttrs(fresh, newCustom.facts, mapperChain);
      domNode.replaceWith(fresh);
      const customState = domState.get(fresh) ?? { listeners: [] };
      domState.set(fresh, { vdomPtr: newResolved | 0, listeners: customState.listeners ?? [] });
      return fresh;
    }

    if (domNode.nodeType !== Node.ELEMENT_NODE) {
      clearListeners(domNode);
      const parent = domNode.parentNode;
      const fresh = mount(parent, newPtr, mapperChain);
      if (fresh) domNode.replaceWith(fresh);
      return fresh;
    }

    const el = domNode;
    clearListeners(el);
    applyAttrs(el, vdomAttrs(newResolved), mapperChain);

    const oldKeyed = oldPtr ? vdomKeyedChildren(oldResolved) : null;
    const newKeyed = vdomKeyedChildren(newResolved);

    if (newKeyed) {
      const oldMap = new Map();
      if (oldKeyed) {
        for (const { key, child } of oldKeyed) oldMap.set(String(key), child);
      }
      const newMap = new Map(newKeyed.map(({ key, child }) => [String(key), child]));
      const childNodes = [...el.childNodes];
      const oldDomByKey = new Map();
      for (const node of childNodes) {
        if (node.__vdomKey != null) oldDomByKey.set(node.__vdomKey, node);
      }

      const nextChildren = [];
      for (const { key, child } of newKeyed) {
        const k = String(key);
        const existingDom = oldDomByKey.get(k);
        const oldChild = oldMap.get(k) ?? 0;
        if (existingDom) {
          patch(oldChild, child, existingDom, mapperChain);
          nextChildren.push(existingDom);
          oldDomByKey.delete(k);
        } else {
          const created = mount(null, child, mapperChain);
          if (created) {
            created.__vdomKey = k;
            nextChildren.push(created);
          }
        }
      }
      for (const orphan of oldDomByKey.values()) orphan.remove();
      for (const node of nextChildren) el.appendChild(node);
      return el;
    }

    const oldChildren = oldPtr ? vdomChildren(oldResolved) : [];
    const newChildren = vdomChildren(newResolved);
    const max = Math.max(oldChildren.length, newChildren.length);
    const childNodes = [...el.childNodes];
    for (let i = 0; i < max; i++) {
      const oldChild = oldChildren[i] ?? 0;
      const newChild = newChildren[i];
      const domChild = childNodes[i];
      if (!newChild) {
        if (domChild) domChild.remove();
        continue;
      }
      if (!domChild) {
        mount(el, newChild, mapperChain);
        continue;
      }
      patch(oldChild, newChild, domChild, mapperChain);
    }
    const patched = domState.get(el) ?? { listeners: [] };
    domState.set(el, { vdomPtr: newResolved | 0, listeners: patched.listeners ?? [] });
    return el;
  };

  return { mount, patch, domState };
}
