/**
 * Browser.application navigation: onUrlChange, onUrlRequest, popstate, link capture.
 */

export function createNavigationRuntime(deps) {
  const {
    RC_SUCCESS,
    invokeClosure,
    dispatchPlatformMsg,
    newIntHandle,
    readHandle,
    unionTagAsInt,
    urlRuntime,
    routeBytes,
    deliverIncomingPort,
    remountBrowserWithRoute,
  } = deps;

  // Pages.Internal.Platform.Msg (1-based): LinkClicked=1, UrlChanged=2, UserMsg=3, …
  // Simple Browser.application fixtures often use UrlChanged=2 when LinkClicked=1.
  const URL_CHANGED_MSG_TAG = 2;

  let navigationKeyPtr = 0;
  let onUrlChangeFn = 0;
  let onUrlRequestFn = 0;
  let linkCaptureDispose = null;
  let popstateDispose = null;
  let suppressNextPopstate = false;
  let pendingPushUrl = null;

  const newNavigationKey = () => {
    navigationKeyPtr = newIntHandle((Math.random() * 0x7fffffff) | 1);
    return navigationKeyPtr;
  };

  const getNavigationKey = () => navigationKeyPtr | 0;

  const probeCallbackMsgTag = (fnPtr, argPtr) => {
    if (!fnPtr || !argPtr || typeof unionTagAsInt !== "function") return -1;
    const result = invokeClosure(fnPtr, [argPtr]);
    if (result.rc !== RC_SUCCESS || !result.value) return -1;
    return unionTagAsInt(result.value);
  };

  const browserUrlCallbacks = (implPtr) => {
    const impl = readHandle(implPtr);
    const fields = impl?.fields ?? [];
    if (fields.length < 6) return { onUrlRequest: 0, onUrlChange: 0 };

    // Alphabetical Browser.application layout:
    // init, onUrlChange, onUrlRequest, subscriptions, update, view
    const onUrlChange = fields[1] | 0;
    const onUrlRequest = fields[2] | 0;

    // Defensive: some older artifacts used declaration order (…, onUrlRequest,
    // onUrlChange at indices 4/5). Probe when alpha slots do not look like Url→msg.
    const probeUrl = urlRuntime.urlFromParts({
      protocol: "http:",
      host: "localhost",
      port: "",
      pathname: "/__elmc_url_cb_probe__",
      search: "",
      hash: "",
    });

    const tagChange = probeCallbackMsgTag(onUrlChange, probeUrl);
    if (tagChange === URL_CHANGED_MSG_TAG) {
      return { onUrlChange, onUrlRequest };
    }

    const field4 = fields[4] | 0;
    const field5 = fields[5] | 0;
    const tag4Url = probeCallbackMsgTag(field4, probeUrl);
    const tag5Url = probeCallbackMsgTag(field5, probeUrl);

    if (tag4Url === URL_CHANGED_MSG_TAG && tag5Url !== URL_CHANGED_MSG_TAG) {
      return { onUrlChange: field4, onUrlRequest: field5 };
    }
    if (tag5Url === URL_CHANGED_MSG_TAG && tag4Url !== URL_CHANGED_MSG_TAG) {
      return { onUrlChange: field5, onUrlRequest: field4 };
    }

    return { onUrlChange, onUrlRequest };
  };

  const invokeUrlChange = async (location) => {
    // elm-pages SPA: FrozenViewsReady on an already-Ok Model currently corrupts
    // platform Model fields under elmc WASM (Ok-branch record update). Remounting
    // reuses the working init + pageDataFromJs (Err→Ok) path instead.
    if (typeof remountBrowserWithRoute === "function" && routeBytes && location) {
      const bytes = routeBytes.lookupFresh
        ? await routeBytes.lookupFresh(location.pathname)
        : await routeBytes.lookup(location.pathname);
      if (bytes) {
        const ok = await remountBrowserWithRoute(location, bytes);
        if (ok) return;
        console.warn("[elmc-nav] remount failed; not applying UrlChanged fallback (unsafe)");
        return;
      }
      console.warn("[elmc-nav] no page bytes for", location.pathname);
    }

    const urlPtr = urlRuntime.urlFromLocation(location);
    if (onUrlChangeFn) {
      const msgResult = invokeClosure(onUrlChangeFn, [urlPtr]);
      if (msgResult.rc === RC_SUCCESS && msgResult.value) {
        dispatchPlatformMsg(msgResult.value);
      }
    }

    if (routeBytes && deliverIncomingPort && location) {
      const bytes = await routeBytes.lookup(location.pathname);
      if (bytes) {
        await deliverIncomingPort("pageDataFromJs", bytes);
      }
    }
  };

  const notifyUrlChangeAfterPush = () => {
    if (typeof window === "undefined") return;
    suppressNextPopstate = true;
    queueMicrotask(() => {
      void invokeUrlChange(window.location);
    });
  };

  const installApplicationNavigation = (implPtr) => {
    if (typeof document === "undefined" || typeof window === "undefined") return;

    const { onUrlRequest, onUrlChange } = browserUrlCallbacks(implPtr);
    onUrlChangeFn = onUrlChange;
    onUrlRequestFn = onUrlRequest;

    if (popstateDispose) popstateDispose();
    if (linkCaptureDispose) linkCaptureDispose();

    const onPopstate = () => {
      if (suppressNextPopstate) {
        suppressNextPopstate = false;
        return;
      }
      void invokeUrlChange(window.location);
    };
    window.addEventListener("popstate", onPopstate);
    popstateDispose = () => {
      if (typeof window.removeEventListener === "function") {
        window.removeEventListener("popstate", onPopstate);
      }
    };

    const onClick = (event) => {
      if (!onUrlRequestFn) return;
      const anchor = event.target?.closest?.("a[href]");
      if (!anchor) return;
      const href = anchor.getAttribute("href");
      if (!href || href.startsWith("#") || href.startsWith("mailto:") || href.startsWith("tel:")) {
        return;
      }
      let targetUrl;
      try {
        targetUrl = new URL(href, window.location.href);
      } catch (_err) {
        return;
      }
      const sameOrigin = targetUrl.origin === window.location.origin;
      if (!sameOrigin) {
        const req = urlRuntime.urlRequestExternal(urlRuntime.newStringHandle(href));
        const msgResult = invokeClosure(onUrlRequestFn, [req]);
        if (msgResult.rc === RC_SUCCESS && msgResult.value) {
          dispatchPlatformMsg(msgResult.value);
        }
        return;
      }
      event.preventDefault();
      const pushPath =
        targetUrl.pathname + (targetUrl.search || "") + (targetUrl.hash || "");
      pendingPushUrl = pushPath;
      const req = urlRuntime.urlRequestInternal(urlRuntime.urlFromLocation(targetUrl));
      const msgResult = invokeClosure(onUrlRequestFn, [req]);
      if (msgResult.rc === RC_SUCCESS && msgResult.value) {
        dispatchPlatformMsg(msgResult.value);
      }
      if (
        typeof window !== "undefined" &&
        pendingPushUrl &&
        window.location.pathname !== pendingPushUrl.split("?")[0].split("#")[0]
      ) {
        const url = pendingPushUrl;
        pendingPushUrl = null;
        window.history.pushState({}, "", url);
        notifyUrlChangeAfterPush();
      }
    };
    document.addEventListener("click", onClick, true);
    linkCaptureDispose = () => document.removeEventListener("click", onClick, true);
  };

  const disposeNavigation = () => {
    try {
      if (popstateDispose) popstateDispose();
    } catch (_err) {
      /* probe / minimal window stubs may lack removeEventListener */
    }
    try {
      if (linkCaptureDispose) linkCaptureDispose();
    } catch (_err) {
      /* same */
    }
    popstateDispose = null;
    linkCaptureDispose = null;
    onUrlChangeFn = 0;
    onUrlRequestFn = 0;
  };

  const consumePendingPushUrl = () => {
    const url = pendingPushUrl;
    pendingPushUrl = null;
    return url;
  };

  return {
    newNavigationKey,
    getNavigationKey,
    installApplicationNavigation,
    notifyUrlChangeAfterPush,
    consumePendingPushUrl,
    disposeNavigation,
    browserUrlCallbacks,
  };
}
