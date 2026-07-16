/**
 * Build decoder arguments for VirtualDom / Html.Events from native DOM events.
 */

export function createDomEventRuntime(deps) {
  const {
    allocHandle,
    newStringHandle,
    newIntHandle,
    tuple2,
    TAG_RECORD,
    TAG_TUPLE2,
    TAG_STRING,
    TAG_INT,
    TAG_MAYBE,
  } = deps;

  const eventRecord = (valuePtrs) =>
    allocHandle({
      tag: TAG_RECORD,
      fields: valuePtrs.map((p) => p | 0),
    });

  const targetValue = (domEvent) => {
    const target = domEvent?.target;
    if (!target) return newStringHandle("");
    if (typeof target.value === "string") return newStringHandle(target.value);
    if (typeof target.value === "number") return newStringHandle(String(target.value));
    return newStringHandle("");
  };

  const targetChecked = (domEvent) => {
    const checked = domEvent?.target?.checked === true;
    return newIntHandle(checked ? 1 : 0);
  };

  const mouseRecord = (domEvent) => {
    const clientX = newIntHandle(domEvent?.clientX | 0);
    const clientY = newIntHandle(domEvent?.clientY | 0);
    const button = newIntHandle(domEvent?.button | 0);
    const buttons = newIntHandle(domEvent?.buttons | 0);
    const ctrlKey = newIntHandle(domEvent?.ctrlKey ? 1 : 0);
    const shiftKey = newIntHandle(domEvent?.shiftKey ? 1 : 0);
    const altKey = newIntHandle(domEvent?.altKey ? 1 : 0);
    const metaKey = newIntHandle(domEvent?.metaKey ? 1 : 0);
    return eventRecord([clientX, clientY, button, buttons, ctrlKey, shiftKey, altKey, metaKey]);
  };

  const keyboardRecord = (domEvent) => {
    const key = newStringHandle(domEvent?.key ?? "");
    const code = newStringHandle(domEvent?.code ?? "");
    const keyCode = newIntHandle(domEvent?.keyCode | 0);
    const ctrlKey = newIntHandle(domEvent?.ctrlKey ? 1 : 0);
    const shiftKey = newIntHandle(domEvent?.shiftKey ? 1 : 0);
    const altKey = newIntHandle(domEvent?.altKey ? 1 : 0);
    const metaKey = newIntHandle(domEvent?.metaKey ? 1 : 0);
    const repeat = newIntHandle(domEvent?.repeat ? 1 : 0);
    return eventRecord([key, code, keyCode, ctrlKey, shiftKey, altKey, metaKey, repeat]);
  };

  const buildDecoderArg = (domEvent, eventName) => {
    const name = (eventName || domEvent?.type || "").toLowerCase();

    if (name === "input" || name === "change") {
      const target = domEvent?.target;
      if (target?.type === "checkbox" || target?.type === "radio") {
        return targetChecked(domEvent);
      }
      return targetValue(domEvent);
    }

    if (name.startsWith("key")) {
      return keyboardRecord(domEvent);
    }

    if (
      name === "click" ||
      name === "dblclick" ||
      name === "mousedown" ||
      name === "mouseup" ||
      name === "mousemove" ||
      name === "pointerdown" ||
      name === "pointerup" ||
      name === "pointermove"
    ) {
      return mouseRecord(domEvent);
    }

    if (name === "submit") {
      return newIntHandle(0);
    }

    if (domEvent?.target?.value != null) {
      return targetValue(domEvent);
    }

    return newIntHandle(0);
  };

  return { buildDecoderArg, targetValue, mouseRecord, keyboardRecord };
}
