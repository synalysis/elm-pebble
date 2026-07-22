/**
 * Multi-route static page bytes manifest for elm-pages WASM boot.
 *
 * Manifest shape (JSON):
 * { "/": "<base64>", "/about": "<base64>", ... }
 * or { "routes": { "/": "<base64>", ... } }
 */

import { decodePageBytesFromHtml, ELM_PAGES_BYTES_ELEMENT_ID } from "./page_bytes.js";

export function createRouteBytesRuntime({ fetchFn = typeof fetch !== "undefined" ? fetch.bind(globalThis) : null } = {}) {
  /** @type {Map<string, Uint8Array>} */
  const staticRoutes = new Map();
  /** @type {((path: string) => Promise<Uint8Array | null>) | null} */
  let runtimeFetcher = null;
  /** @type {string | null} */
  let siteRootUrl = null;

  const normalizeRoutePath = (path) => {
    if (!path || path === "/") return "/";
    let p = path.split("?")[0].split("#")[0];
    if (!p.startsWith("/")) p = `/${p}`;
    if (p.length > 1 && p.endsWith("/")) p = p.slice(0, -1);
    return p;
  };

  const decodeBase64 = (base64) => {
    if (typeof Buffer !== "undefined") {
      return new Uint8Array(Buffer.from(base64, "base64"));
    }
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
  };

  const loadManifest = async (manifestUrl) => {
    if (!manifestUrl || !fetchFn) return;
    try {
      const response = await fetchFn(manifestUrl);
      if (!response.ok) return;
      const json = await response.json();
      const routes = json.routes ?? json;
      for (const [path, b64] of Object.entries(routes)) {
        if (typeof b64 === "string") {
          staticRoutes.set(normalizeRoutePath(path), decodeBase64(b64));
        }
      }
    } catch (err) {
      console.warn("[elmc-wasm-runtime] failed to load route bytes manifest", err);
    }
  };

  const registerRoute = (path, bytes) => {
    if (bytes) staticRoutes.set(normalizeRoutePath(path), bytes);
  };

  const setRuntimeFetcher = (fn) => {
    runtimeFetcher = typeof fn === "function" ? fn : null;
  };

  const setSiteRootFromPageHtml = (pageHtmlUrl) => {
    if (!pageHtmlUrl) {
      siteRootUrl = null;
      return;
    }
    try {
      // Site root is the deploy root that contains every `/$route/content.dat`,
      // not the directory of the page we happened to boot from. Deep-linking
      // `/getting-started` must not make later nav fetch
      // `/getting-started/f-a-q/content.dat`.
      const url = new URL(pageHtmlUrl);
      let path = url.pathname.replace(/\/+$/, "") || "";
      if (path.endsWith("/index.html")) {
        path = path.slice(0, -"/index.html".length);
      } else if (path.endsWith(".html")) {
        path = path.slice(0, -path.split("/").pop().length - 1);
      }
      // path is "" (site index) or "/getting-started" (route page) or
      // "/wasm-web/host" (direct host shell). Route pages and the host shell
      // walk up to the deploy root; site index stays at origin/.
      if (path.startsWith("/wasm-web/")) {
        siteRootUrl = `${url.origin}/`;
        return;
      }
      if (path !== "" && path !== "/") {
        // Parent of the route folder.
        siteRootUrl = new URL("..", `${url.origin}${path}/`).href;
        if (!siteRootUrl.endsWith("/")) siteRootUrl = `${siteRootUrl}/`;
        return;
      }
      siteRootUrl = `${url.origin}/`;
    } catch {
      siteRootUrl = null;
    }
  };

  const siteRootDir = () => {
    if (siteRootUrl) return siteRootUrl;
    if (typeof document === "undefined") return null;
    // Never derive from the current route path — trailing `/getting-started/`
    // would otherwise prefix every content.dat fetch.
    try {
      return `${new URL(document.baseURI || window.location.href).origin}/`;
    } catch {
      return null;
    }
  };

  const lookup = async (path) => {
    const key = normalizeRoutePath(path);
    const cached = staticRoutes.get(key);
    if (cached) return cached;
    if (runtimeFetcher) {
      const fetched = await runtimeFetcher(key);
      if (fetched) {
        staticRoutes.set(key, fetched);
        return fetched;
      }
    }
    return null;
  };

  /** Like lookup but always refreshes from the runtime fetcher (SPA remount). */
  const lookupFresh = async (path) => {
    const key = normalizeRoutePath(path);
    if (runtimeFetcher) {
      const fetched = await runtimeFetcher(key);
      if (fetched) {
        staticRoutes.set(key, fetched);
        return fetched;
      }
    }
    return staticRoutes.get(key) ?? null;
  };

  const fetchFromHtmlUrl = async (htmlUrl) => {
    if (!fetchFn || !htmlUrl) return null;
    try {
      const response = await fetchFn(htmlUrl);
      if (!response.ok) return null;
      const html = await response.text();
      return decodePageBytesFromHtml(html);
    } catch (_err) {
      return null;
    }
  };

  /** Parse content.dat frozen-views prefix into window.__ELM_PAGES_FROZEN_VIEWS__. */
  const applyFrozenViewsFromContentDat = (buffer) => {
    if (typeof window === "undefined" || !buffer || buffer.byteLength < 4) return;
    try {
      const view = new DataView(buffer.buffer, buffer.byteOffset, buffer.byteLength);
      const frozenLen = view.getUint32(0, false);
      if (frozenLen < 0 || 4 + frozenLen > buffer.byteLength) return;
      const frozenBytes = new Uint8Array(buffer.buffer, buffer.byteOffset + 4, frozenLen);
      const frozenJson = new TextDecoder().decode(frozenBytes);
      window.__ELM_PAGES_FROZEN_VIEWS__ = JSON.parse(frozenJson);
    } catch (_err) {
      /* ignore malformed prefix — Elm decoder still gets the full buffer */
    }
  };

  /** elm-pages SPA contract: `${origin}${path}/content.dat` (full buffer for pageDataFromJs). */
  const fetchFromContentDat = async (path) => {
    if (!fetchFn) return null;
    const dir = siteRootDir();
    if (!dir) return null;
    const suffix = path === "/" ? "content.dat" : `${path.slice(1)}/content.dat`;
    const url = `${dir}${suffix}`;
    try {
      const response = await fetchFn(url);
      if (!response.ok) return null;
      const buffer = await response.arrayBuffer();
      if (!buffer || buffer.byteLength === 0) return null;
      const bytes = new Uint8Array(buffer);
      applyFrozenViewsFromContentDat(bytes);
      return bytes;
    } catch (_err) {
      return null;
    }
  };

  const defaultRuntimeFetcher = async (path) => {
    if (!fetchFn) return null;
    // Prefer content.dat (same payload elm-pages sends on FetchFrozenViews).
    const fromDat = await fetchFromContentDat(path);
    if (fromDat) return fromDat;

    if (typeof document === "undefined") return null;
    const dir = siteRootDir();
    if (!dir) return null;
    const candidates = [
      path === "/" ? `${dir}index.html` : `${dir}${path.slice(1)}/index.html`,
      `${dir}${path.slice(1)}.html`,
    ];
    for (const url of candidates) {
      const bytes = await fetchFromHtmlUrl(url);
      if (bytes) return bytes;
    }
    return null;
  };

  return {
    loadManifest,
    registerRoute,
    setRuntimeFetcher,
    setSiteRootFromPageHtml,
    lookup,
    lookupFresh,
    normalizeRoutePath,
    defaultRuntimeFetcher,
    applyFrozenViewsFromContentDat,
    ELM_PAGES_BYTES_ELEMENT_ID,
  };
}
