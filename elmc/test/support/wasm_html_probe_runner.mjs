import { readFileSync } from "node:fs";
import { loadElmcWasm, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";

const [buildDir, exportName, expectedText] = process.argv.slice(2);

if (!buildDir || !exportName) {
  console.error("usage: wasm_html_probe_runner.mjs <buildDir> <exportName> [expectedText]");
  process.exit(2);
}

const manifest = JSON.parse(
  readFileSync(`${buildDir}/wasm/elmc_wasm.manifest.json`, "utf8")
);

let wasmBytes;
try {
  wasmBytes = readFileSync(`${buildDir}/wasm/app.wasm`);
} catch (_err) {
  wasmBytes = readFileSync(`${buildDir}/wasm/elmc_generated.wasm`);
}

const { helpers, callExport } = await loadElmcWasm({
  wasmBytes,
  manifestImports: manifest.imports || [],
  manifestClosures: manifest.closures || [],
  immortalStrings: manifest.immortal_strings || {},
});

const { rc, value: resultHandle } = callExport(exportName, []);

if (rc !== RC_SUCCESS) {
  console.error(`probe failed: rc=${rc}`);
  process.exit(1);
}

const vdom = helpers.inspectVdom(resultHandle);

if (!vdom) {
  console.error("probe failed: export did not return a vdom handle");
  process.exit(1);
}

helpers.buildImport("release")(resultHandle);

if (!helpers.checkBalanced()) {
  console.error("rc leak detected after probe");
  process.exit(1);
}

if (expectedText !== undefined) {
  if (vdom.kind === "text" && vdom.text !== expectedText) {
    console.error(`vdom text mismatch: got ${JSON.stringify(vdom.text)}, expected ${JSON.stringify(expectedText)}`);
    process.exit(1);
  }

  if (vdom.kind === "node" && vdom.innerText !== expectedText) {
    console.error(`vdom innerText mismatch: got ${JSON.stringify(vdom.innerText)}, expected ${JSON.stringify(expectedText)}`);
    process.exit(1);
  }
}

if (vdom.kind === "text") {
  console.log(`rc_ok vdom_text=${vdom.text}`);
} else if (vdom.kind === "node") {
  const attrs =
    vdom.attrs && vdom.attrs.length > 0
      ? ` attrs=${JSON.stringify(vdom.attrs)}`
      : "";
  console.log(
    `rc_ok vdom_node=${vdom.tagName} children=${vdom.childCount} innerText=${JSON.stringify(vdom.innerText)}${attrs}`
  );
} else if (vdom.kind === "attr") {
  console.log(`rc_ok vdom_attr=${vdom.name}=${JSON.stringify(vdom.value)}`);
} else {
  console.log(`rc_ok vdom_${vdom.kind}=${JSON.stringify(vdom)}`);
}
