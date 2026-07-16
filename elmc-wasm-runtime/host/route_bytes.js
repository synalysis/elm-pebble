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
      siteRootUrl = new URL("./", pageHtmlUrl).href;
    } catch {
      siteRootUrl = null;
    }
  };

  const siteRootDir = () => {
    if (siteRootUrl) return siteRootUrl;
    if (typeof document === "undefined") return null;
    const base = document.baseURI || window.location.href;
    return base.replace(/\/[^/]*$/, "/");
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

  const defaultRuntimeFetcher = async (path) => {
    if (!fetchFn || typeof document === "undefined") return null;
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
    normalizeRoutePath,
    defaultRuntimeFetcher,
    ELM_PAGES_BYTES_ELEMENT_ID,
  };
}
