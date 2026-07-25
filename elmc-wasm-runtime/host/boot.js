import { loadElmcWasm, RC_SUCCESS } from "./loader.js";
import { decodePageBytesFromHtml } from "./page_bytes.js";
import { injectPageStylesFromHtml } from "./page_styles.js";

function publishBootTiming(timing) {
  if (typeof globalThis === "undefined") return;
  globalThis.__elmcBootTiming = timing;
}

async function fetchManifest(url, fetchFn) {
  const response = await fetchFn(url);
  if (!response.ok) {
    throw new Error(`failed to load manifest: ${response.status}`);
  }
  return response.json();
}

async function fetchWasmResponse(url, fetchFn) {
  const response = await fetchFn(url);
  if (!response.ok) {
    throw new Error(`failed to load ${url}: ${response.status}`);
  }
  return response;
}

/** Load page bytes (prefer content.dat) plus HTML for style injection. */
async function loadPageBundle(htmlUrl, fetchFn) {
  if (!htmlUrl) {
    return { html: null, pageBytes: null };
  }

  let contentDatUrl = null;
  try {
    const html = new URL(htmlUrl);
    if (html.pathname.endsWith("index.html")) {
      // …/index.html → …/content.dat (elm-pages SPA contract)
      contentDatUrl = new URL("./content.dat", html).href;
    }
  } catch {
    contentDatUrl = null;
  }

  const htmlPromise = fetchFn(htmlUrl)
    .then(async (response) => (response.ok ? response.text() : null))
    .catch(() => null);

  const datPromise = contentDatUrl
    ? fetchFn(contentDatUrl)
        .then(async (response) => {
          if (!response.ok) return null;
          const buffer = await response.arrayBuffer();
          return buffer.byteLength > 0 ? new Uint8Array(buffer) : null;
        })
        .catch(() => null)
    : Promise.resolve(null);

  const [html, datBytes] = await Promise.all([htmlPromise, datPromise]);
  const pageBytes = datBytes ?? (html ? decodePageBytesFromHtml(html) : null);
  return { html, pageBytes };
}

export async function bootFromUrls({
  manifestUrl,
  wasmUrl,
  exportName,
  pageHtmlUrl,
  /** Deploy root (directory that contains `/`, `/getting-started/`, …). */
  siteRootUrl,
  pageBytes,
  pageBundlePromise,
  fetchFn,
}) {
  const fetchImpl = fetchFn ?? fetch;
  const t0 = performance.now();

  // Overlap manifesto JSON, wasm Response (for compileStreaming), and page HTML.
  const manifestPromise = fetchManifest(manifestUrl, fetchImpl);
  const wasmPromise = fetchWasmResponse(wasmUrl, fetchImpl);
  const bundlePromise =
    pageBundlePromise ??
    (pageBytes != null
      ? Promise.resolve({ html: null, pageBytes })
      : pageHtmlUrl
        ? loadPageBundle(pageHtmlUrl, fetchImpl)
        : Promise.resolve({ html: null, pageBytes: null }));

  const [manifest, wasmResponse, pageBundle] = await Promise.all([
    manifestPromise,
    wasmPromise,
    bundlePromise,
  ]);
  const fetchMs = performance.now() - t0;

  if (manifest.route_bytes_manifest && typeof document !== "undefined") {
    try {
      await fetchImpl(manifest.route_bytes_manifest).then(async (response) => {
        if (!response.ok) return;
        const json = await response.json();
        const routes = json.routes ?? json;
        for (const [path, b64] of Object.entries(routes)) {
          if (typeof b64 !== "string") continue;
          const binary = atob(b64);
          const bytes = new Uint8Array(binary.length);
          for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
          pageBundle.routeBytes = pageBundle.routeBytes ?? new Map();
          pageBundle.routeBytes.set(path, bytes);
        }
      });
    } catch (err) {
      console.warn("failed to preload route bytes manifest", err);
    }
  }

  if (pageBundle?.html && typeof document !== "undefined") {
    try {
      injectPageStylesFromHtml(pageBundle.html, pageHtmlUrl);
    } catch (err) {
      console.warn("failed to inject page styles", err);
    }
  }

  const entry = exportName || manifest.entry_export || "elmc_fn_Main_main";

  const { helpers, callExport, timing: loadTiming } = await loadElmcWasm({
    wasmResponse,
    manifestImports: manifest.imports || [],
    manifestClosures: manifest.closures || [],
    closureCount: manifest.closure_count ?? null,
    immortalStrings: manifest.immortal_strings || {},
    constructorTags: manifest.constructor_tags || {},
  });
  // Prefer explicit deploy root so deep-link boots do not pin content.dat under
  // the first route (e.g. /getting-started/f-a-q/content.dat).
  const rootForRouteBytes =
    siteRootUrl != null
      ? new URL("index.html", siteRootUrl).href
      : pageHtmlUrl;
  if (rootForRouteBytes) {
    helpers.setRouteBytesSiteRoot?.(rootForRouteBytes);
  }
  const afterLoadMs = performance.now() - t0;

  const tEntry = performance.now();
  const { rc, value } = callExport(entry, []);
  if (rc !== RC_SUCCESS) {
    throw new Error(`export ${entry} failed: rc=${rc}`);
  }
  const entryMs = performance.now() - tEntry;

  if (helpers.isBrowserProgram(value)) {
    let bootOpts = {};
    const loadedPageBytes = pageBundle?.pageBytes ?? null;
    if (loadedPageBytes) {
      // Cache under the actual route only. Registering a deep-link's bytes as "/"
      // poisons later SPA remounts back to the homepage (route/pageData mismatch).
      if (pageHtmlUrl) {
        try {
          const pagePath = new URL(pageHtmlUrl).pathname;
          const routePath =
            pagePath.endsWith("/index.html")
              ? pagePath.slice(0, -"/index.html".length) || "/"
              : pagePath.endsWith(".html")
                ? pagePath.slice(0, -".html".length) || "/"
                : "/";
          helpers.registerRouteBytes?.(routePath || "/", loadedPageBytes);
        } catch {
          helpers.registerRouteBytes?.("/", loadedPageBytes);
        }
      } else {
        helpers.registerRouteBytes?.("/", loadedPageBytes);
      }
      const bytesHandle = helpers.newBytesFromUint8Array(loadedPageBytes);
      bootOpts = { incomingPorts: { pageDataFromJs: bytesHandle } };
    } else if (pageHtmlUrl) {
      console.warn(`page bytes not found at ${pageHtmlUrl}; booting without pageDataFromJs`);
    }

    if (pageBundle?.routeBytes instanceof Map) {
      for (const [path, bytes] of pageBundle.routeBytes.entries()) {
        helpers.registerRouteBytes?.(path, bytes);
      }
    }

    if (manifest.route_bytes_manifest && helpers.loadRouteBytesManifest) {
      await helpers.loadRouteBytesManifest(
        new URL(manifest.route_bytes_manifest, manifestUrl).href
      );
    }

    const tBoot = performance.now();
    const boot = helpers.bootBrowserProgram(value, {
      ...bootOpts,
      // Browser readiness uses DOM (`document.title` + `<main>`); skip the
      // full VDOM text walk unless a probe explicitly needs `innerText`.
      skipInnerText: typeof document !== "undefined",
      omitPortRcWalk: typeof document !== "undefined",
    });
    const browserBootMs = performance.now() - tBoot;
    if (boot.rc !== RC_SUCCESS) {
      throw new Error(
        `browser program boot failed: rc=${boot.rc} stage=${boot.stage ?? "unknown"}`
      );
    }

    if (boot.title && typeof document !== "undefined") {
      document.title = boot.title;
    }

    const outgoing = helpers.drainOutgoingPorts?.() ?? boot.outgoingPorts ?? [];
    if (outgoing.length > 0) {
      console.debug("[elmc-wasm-runtime] outgoing ports at boot", outgoing);
    }

    helpers.buildImport("release")(value);
    // Live browser owns model + mounted view (retained in liveBrowser). Releasing
    // them here freed lastBodyPtrs and the next Time.every patch remounted WebGL
    // via replaceWith + replaceChild → NotFoundError and a blank white canvas.
    if (boot.initValue && boot.initValue !== boot.modelPtr && boot.initValue !== boot.value) {
      helpers.buildImport("release")(boot.initValue);
    }

    // Browser programs intentionally keep non-immortal model/view/subs alive.
    // checkBalanced() is for one-shot VDOM mounts, not the live SPA session.
    const timing = {
      total_ms: +(performance.now() - t0).toFixed(1),
      fetch_ms: +fetchMs.toFixed(1),
      compile_ms: loadTiming?.compile_ms ?? null,
      instantiate_ms: loadTiming?.instantiate_ms ?? null,
      compile_mode: loadTiming?.compile_mode ?? null,
      after_load_ms: +afterLoadMs.toFixed(1),
      entry_ms: +entryMs.toFixed(1),
      browser_boot_ms: +browserBootMs.toFixed(1),
      browser_boot_phases: boot.phases ?? null,
    };
    publishBootTiming(timing);

    return {
      exportName: entry,
      innerText: boot.innerText,
      title: boot.title ?? "",
      kind: "browser_program",
      timing,
    };
  }

  helpers.mountVdomToApp(value);
  helpers.buildImport("release")(value);

  if (!helpers.checkBalanced()) {
    throw new Error("RC leak after mounting view");
  }

  const timing = {
    total_ms: +(performance.now() - t0).toFixed(1),
    fetch_ms: +fetchMs.toFixed(1),
    compile_ms: loadTiming?.compile_ms ?? null,
    instantiate_ms: loadTiming?.instantiate_ms ?? null,
    compile_mode: loadTiming?.compile_mode ?? null,
    after_load_ms: +afterLoadMs.toFixed(1),
    entry_ms: +entryMs.toFixed(1),
    browser_boot_ms: null,
  };
  publishBootTiming(timing);

  return {
    exportName: entry,
    innerText: helpers.vdomInnerText(value),
    title: "",
    kind: "vdom",
    timing,
  };
}

if (typeof document !== "undefined") {
  const showError = (err) => {
    const el = document.getElementById("boot-error");
    if (el) {
      el.hidden = false;
      el.textContent = String(err?.stack || err);
    }
    console.error(err);
  };

  const siteRoot = new URL("../../", import.meta.url);
  const defaultPageHtml = new URL("index.html", siteRoot).href;

  const resolveBootPageHtml = () => {
    const pageHtmlParam = new URLSearchParams(location.search).get("pageHtml");
    if (pageHtmlParam) {
      try {
        return new URL(pageHtmlParam, location.href).href;
      } catch {
        return defaultPageHtml;
      }
    }

    // SPA deep link: static server rewrites `/getting-started` → this host shell while
    // keeping the route pathname. Boot that route's HTML (styles + embedded bytes).
    const hostPrefix = new URL("./", import.meta.url).pathname.replace(/\/$/, "");
    const path = (location.pathname || "/").replace(/\/$/, "") || "/";
    if (path === "/" || path === hostPrefix || path.startsWith(`${hostPrefix}/`)) {
      return defaultPageHtml;
    }
    return new URL(`${path.slice(1)}/index.html`, siteRoot).href;
  };

  const pageHtmlUrl = resolveBootPageHtml();
  const fetchImpl = fetch;
  // Start HTML fetch immediately so styles+bytes share one transfer with wasm/manifest.
  const pageBundlePromise = loadPageBundle(pageHtmlUrl, fetchImpl);

  bootFromUrls({
    manifestUrl: new URL("../wasm/elmc_wasm.manifest.json", import.meta.url).href,
    wasmUrl: new URL("../wasm/app.wasm", import.meta.url).href,
    pageHtmlUrl,
    siteRootUrl: siteRoot.href,
    pageBundlePromise,
    fetchFn: fetchImpl,
  }).catch(showError);
}
