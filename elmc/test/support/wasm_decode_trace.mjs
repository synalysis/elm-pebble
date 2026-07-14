import { readFileSync } from "node:fs";
import { loadElmcWasm } from "../../../elmc-wasm-runtime/host/loader.js";

const TAG = {
  INT: 1,
  MAYBE: 3,
  CLOSURE: 5,
  TUPLE2: 6,
  STRING: 7,
  RECORD: 11,
  BYTES: 16,
};

function describe(readHandle, ptr, depth = 0, seen = new Set()) {
  if (!ptr || seen.has(ptr)) return String(ptr ?? "0");
  seen.add(ptr);
  const p = readHandle(ptr);
  if (!p) return `raw(${ptr})`;
  switch (p.tag) {
    case TAG.INT:
      return `Int(${p.value})`;
    case TAG.TUPLE2:
      return `T2(${describe(readHandle, p.first, depth + 1, seen)}, ${describe(readHandle, p.second, depth + 1, seen)})`;
    case TAG.MAYBE:
      return p.value == null
        ? "Nothing"
        : `Just(${describe(readHandle, p.value, depth + 1, seen)})`;
    case TAG.CLOSURE:
      return `Closure(fn=${p.fnIndex}, arity=${p.arity}, cap=${(p.captures ?? []).length})`;
    case TAG.STRING:
      return `Str(${JSON.stringify(String(p.value).slice(0, 80))})`;
    case TAG.RECORD:
      return `Record(${p.fields?.length})`;
    case TAG.BYTES:
      return `Bytes(${p.view?.byteLength})[${[
        ...new Uint8Array(
          p.view?.buffer ?? [],
          p.view?.byteOffset ?? 0,
          p.view?.byteLength ?? 0
        ),
      ].join(",")}]`;
    default:
      return `tag${p.tag}(h=${ptr})`;
  }
}

const buildDir = process.argv[2] ?? "/tmp/elm_pebble_dev_wasm";
const manifest = JSON.parse(
  readFileSync(`${buildDir}/wasm/elmc_wasm.manifest.json`, "utf8")
);
const wasmBytes = readFileSync(`${buildDir}/wasm/app.wasm`);
const { helpers, callExport, memory } = await loadElmcWasm({
  wasmBytes,
  manifestImports: manifest.imports ?? [],
  manifestClosures: manifest.closures ?? [],
  immortalStrings: manifest.immortal_strings ?? {},
});

const { readHandle, buildImport, newBytesFromUint8Array } = helpers;
const view = () => new DataView(memory.buffer);
const readOut = (p) => view().getUint32(p, true);
const d = (p) => describe(readHandle, p);

const html = readFileSync("elm_pebble_dev/dist/index.html", "utf8");
const pageBytes = Buffer.from(
  html.match(/id="__ELM_PAGES_BYTES_DATA__"[^>]*>([^<]+)</)[1],
  "base64"
);
console.log("embedded", [...pageBytes]);

const dr = callExport("elmc_fn_Main_decodeResponse", []);
console.log("decodeResponse", d(dr.value));

const bytesHandle = newBytesFromUint8Array(new Uint8Array(pageBytes));

const offsetScratch = 9000;
buildImport("new_int")(offsetScratch, 0);
const offsetHandle = readOut(offsetScratch);

// invoke inner decoder closure directly
const dec = readHandle(dr.value);
const inner = dec?.second;
if (inner) {
  const scratch = 9012;
  buildImport("call_closure")(
    scratch,
    2,
    inner,
    bytesHandle,
    offsetHandle
  );
  console.log(
    "inner decoder call_closure rc ok, result",
    d(readOut(scratch))
  );
}

const scratch = 9024;
const rc = buildImport("bytes_cmd")(scratch, 5, dr.value, bytesHandle);
console.log("bytes_cmd decode rc", rc, "result", d(readOut(scratch)));

// Try swapped tuple interpretation on inner result
const innerResult = readOut(9012);
const payload = readHandle(innerResult);
if (payload?.tag === TAG.TUPLE2) {
  console.log(
    "tuple first (as offset?)",
    d(payload.first),
    "second (as value?)",
    d(payload.second)
  );
  console.log(
    "SWAPPED: first as value",
    d(payload.first),
    "second as offset",
    d(payload.second)
  );
}
