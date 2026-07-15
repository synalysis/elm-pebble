import { decodePageBytesFromHtml, ELM_PAGES_BYTES_ELEMENT_ID } from "../../../elmc-wasm-runtime/host/page_bytes.js";

const sampleHtml = `<html><body><script type="application/json" id="${ELM_PAGES_BYTES_ELEMENT_ID}">AQID</script></body></html>`;
const bytes = decodePageBytesFromHtml(sampleHtml);

if (!bytes || bytes.length !== 3) {
  console.error(`decodePageBytesFromHtml failed: ${bytes}`);
  process.exit(1);
}

if (bytes[0] !== 1 || bytes[1] !== 2 || bytes[2] !== 3) {
  console.error(`unexpected bytes: ${[...bytes]}`);
  process.exit(1);
}

if (decodePageBytesFromHtml("<html></html>") !== null) {
  console.error("expected null for missing element");
  process.exit(1);
}

console.log("rc_ok page_bytes_self_test");
