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

/** One fetch of index.html → page bytes (+ optional shared HTML for styles). */
async function loadPageBundle(htmlUrl, fetchFn) {
  if (!htmlUrl) {
    return { html: null, pageBytes: null };
  }
  const response = await fetchFn(htmlUrl);
  if (!response.ok) {
    return { html: null, pageBytes: null };
  }
  const html = await response.text();
  return { html, pageBytes: decodePageBytesFromHtml(html) };
}

export async function bootFromUrls({
  manifestUrl,
  wasmUrl,
  exportName,
  pageHtmlUrl,
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
  if (pageHtmlUrl) {
    helpers.setRouteBytesSiteRoot?.(pageHtmlUrl);
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
      helpers.registerRouteBytes?.("/", loadedPageBytes);
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
    if (boot.value) helpers.buildImport("release")(boot.value);
    if (boot.initValue) helpers.buildImport("release")(boot.initValue);
    else if (boot.modelPtr) helpers.buildImport("release")(boot.modelPtr);

    if (!helpers.checkBalanced()) {
      console.warn("RC imbalance after mounting browser program");
    }

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

  const pageHtmlParam = new URLSearchParams(location.search).get("pageHtml");
  const defaultPageHtml = new URL("../../index.html", import.meta.url).href;
  const pageHtmlUrl = pageHtmlParam || defaultPageHtml;
  const fetchImpl = fetch;
  // Start HTML fetch immediately so styles+bytes share one transfer with wasm/manifest.
  const pageBundlePromise = loadPageBundle(pageHtmlUrl, fetchImpl);

  bootFromUrls({
    manifestUrl: new URL("../wasm/elmc_wasm.manifest.json", import.meta.url).href,
    wasmUrl: new URL("../wasm/app.wasm", import.meta.url).href,
    pageHtmlUrl,
    pageBundlePromise,
    fetchFn: fetchImpl,
  }).catch(showError);
}
