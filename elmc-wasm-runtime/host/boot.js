import { loadElmcWasm, RC_SUCCESS } from "./loader.js";

async function loadBytes(url) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`failed to load ${url}: ${response.status}`);
  }
  return new Uint8Array(await response.arrayBuffer());
}

export async function bootFromUrls({ manifestUrl, wasmUrl, exportName }) {
  const manifestResponse = await fetch(manifestUrl);
  if (!manifestResponse.ok) {
    throw new Error(`failed to load manifest: ${manifestResponse.status}`);
  }
  const manifest = await manifestResponse.json();
  const wasmBytes = await loadBytes(wasmUrl);
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
    const boot = helpers.bootBrowserProgram(value);
    if (boot.rc !== RC_SUCCESS) {
      throw new Error(`browser program boot failed: rc=${boot.rc} stage=${boot.stage ?? "unknown"}`);
    }

    helpers.buildImport("release")(value);
    if (boot.value) helpers.buildImport("release")(boot.value);
    if (boot.initValue) helpers.buildImport("release")(boot.initValue);
    else if (boot.modelPtr) helpers.buildImport("release")(boot.modelPtr);

    if (!helpers.checkBalanced()) {
      throw new Error("RC leak after mounting browser program");
    }

    return { exportName: entry, innerText: boot.innerText, kind: "browser_program" };
  }

  helpers.mountVdomToApp(value);
  helpers.buildImport("release")(value);

  if (!helpers.checkBalanced()) {
    throw new Error("RC leak after mounting view");
  }

  return { exportName: entry, innerText: helpers.vdomInnerText(value), kind: "vdom" };
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

  bootFromUrls({
    manifestUrl: new URL("../wasm/elmc_wasm.manifest.json", import.meta.url).href,
    wasmUrl: new URL("../wasm/app.wasm", import.meta.url).href,
  }).catch(showError);
}
