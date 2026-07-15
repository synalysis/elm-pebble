import { loadElmcWasm, RC_SUCCESS } from "./loader.js";
import { loadPageBytesFromHtmlUrl } from "./page_bytes.js";
import { injectPageStylesFromHtmlUrl } from "./page_styles.js";

async function loadBytes(url, fetchFn = fetch) {
  const response = await fetchFn(url);
  if (!response.ok) {
    throw new Error(`failed to load ${url}: ${response.status}`);
  }
  return new Uint8Array(await response.arrayBuffer());
}

export async function bootFromUrls({
  manifestUrl,
  wasmUrl,
  exportName,
  pageHtmlUrl,
  pageBytes,
  fetchFn,
}) {
  const fetchImpl = fetchFn ?? fetch;
  const manifestResponse = await fetchImpl(manifestUrl);
  if (!manifestResponse.ok) {
    throw new Error(`failed to load manifest: ${manifestResponse.status}`);
  }
  const manifest = await manifestResponse.json();
  const wasmBytes = await loadBytes(wasmUrl, fetchImpl);
  const entry = exportName || manifest.entry_export || "elmc_fn_Main_main";

  const { helpers, callExport } = await loadElmcWasm({
    wasmBytes,
    manifestImports: manifest.imports || [],
    manifestClosures: manifest.closures || [],
    immortalStrings: manifest.immortal_strings || {},
  });

  const { rc, value } = callExport(entry, []);
  if (rc !== RC_SUCCESS) {
    throw new Error(`export ${entry} failed: rc=${rc}`);
  }

  if (helpers.isBrowserProgram(value)) {
    let bootOpts = {};

    if (pageBytes) {
      const bytesHandle = helpers.newBytesFromUint8Array(pageBytes);
      bootOpts = { incomingPorts: { pageDataFromJs: bytesHandle } };
    } else if (pageHtmlUrl) {
      const loaded = await loadPageBytesFromHtmlUrl(pageHtmlUrl, fetchImpl);
      if (loaded) {
        const bytesHandle = helpers.newBytesFromUint8Array(loaded);
        bootOpts = { incomingPorts: { pageDataFromJs: bytesHandle } };
      } else {
        console.warn(`page bytes not found at ${pageHtmlUrl}; booting without pageDataFromJs`);
      }
    }

    const boot = helpers.bootBrowserProgram(value, bootOpts);
    if (boot.rc !== RC_SUCCESS) {
      throw new Error(
        `browser program boot failed: rc=${boot.rc} stage=${boot.stage ?? "unknown"}`
      );
    }

    if (boot.title && typeof document !== "undefined") {
      document.title = boot.title;
    }

    helpers.buildImport("release")(value);
    if (boot.value) helpers.buildImport("release")(boot.value);
    if (boot.initValue) helpers.buildImport("release")(boot.initValue);
    else if (boot.modelPtr) helpers.buildImport("release")(boot.modelPtr);

    if (!helpers.checkBalanced()) {
      console.warn("RC imbalance after mounting browser program");
    }

    return {
      exportName: entry,
      innerText: boot.innerText,
      title: boot.title ?? "",
      kind: "browser_program",
    };
  }

  helpers.mountVdomToApp(value);
  helpers.buildImport("release")(value);

  if (!helpers.checkBalanced()) {
    throw new Error("RC leak after mounting view");
  }

  return {
    exportName: entry,
    innerText: helpers.vdomInnerText(value),
    title: "",
    kind: "vdom",
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

  injectPageStylesFromHtmlUrl(pageHtmlUrl)
    .catch((err) => {
      console.warn("failed to load page styles from", pageHtmlUrl, err);
    })
    .finally(() => {
      bootFromUrls({
        manifestUrl: new URL("../wasm/elmc_wasm.manifest.json", import.meta.url).href,
        wasmUrl: new URL("../wasm/app.wasm", import.meta.url).href,
        pageHtmlUrl,
      }).catch(showError);
    });
}
