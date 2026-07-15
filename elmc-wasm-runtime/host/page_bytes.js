/** Shared elm-pages route bytes extraction for browser boot and Node probes. */

export const ELM_PAGES_BYTES_ELEMENT_ID = "__ELM_PAGES_BYTES_DATA__";

export function decodePageBytesFromHtml(html) {
  const match = html.match(
    new RegExp(`id="${ELM_PAGES_BYTES_ELEMENT_ID}"[^>]*>([^<]+)<`)
  );
  if (!match) {
    return null;
  }

  const base64 = match[1];

  if (typeof Buffer !== "undefined") {
    return new Uint8Array(Buffer.from(base64, "base64"));
  }

  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

export async function loadPageBytesFromHtmlUrl(htmlUrl, fetchFn = fetch) {
  if (!htmlUrl) {
    return null;
  }

  const response = await fetchFn(htmlUrl);
  if (!response.ok) {
    return null;
  }

  const html = await response.text();
  return decodePageBytesFromHtml(html);
}
