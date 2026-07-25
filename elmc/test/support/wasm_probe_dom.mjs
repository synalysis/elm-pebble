/**
 * Minimal DOM for wasm browser probes that assert on #app textContent.
 */
import { parseHTML } from "linkedom";

export function installProbeDocument(html = "<!doctype html><html><body><div id='app'></div></body></html>") {
  const { document } = parseHTML(html);
  globalThis.document = document;
  if (document.defaultView) {
    globalThis.Node = document.defaultView.Node;
    globalThis.window = document.defaultView;
  }
  return document;
}
