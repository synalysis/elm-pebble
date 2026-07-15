/** Pull elm-pages build CSS + layout helpers from dist/index.html into WASM preview. */

function resolveAssetUrl(href, baseUrl) {
  if (!href) return null;
  try {
    return new URL(href, baseUrl).href;
  } catch {
    return null;
  }
}

function ensureHeadLink(doc, href) {
  if (!href || !doc?.head) return;
  if ([...doc.head.querySelectorAll('link[rel="stylesheet"]')].some((el) => el.href === href)) {
    return;
  }
  const link = doc.createElement("link");
  link.rel = "stylesheet";
  link.href = href;
  doc.head.appendChild(link);
}

function ensureHeadStyle(doc, cssText, key) {
  if (!cssText?.trim() || !doc?.head) return;
  const id = key ? `elmc-wasm-preview-${key}` : null;
  if (id && doc.getElementById(id)) return;
  const style = doc.createElement("style");
  if (id) style.id = id;
  style.textContent = cssText;
  doc.head.appendChild(style);
}

function ensureHeadScript(doc, scriptText, key) {
  if (!scriptText?.trim() || !doc?.head) return;
  const id = key ? `elmc-wasm-preview-${key}` : null;
  if (id && doc.getElementById(id)) return;
  const script = doc.createElement("script");
  if (id) script.id = id;
  script.textContent = scriptText;
  doc.head.appendChild(script);
}

function ensureMeta(doc, name, content) {
  if (!name || !content || !doc?.head) return;
  let meta = doc.head.querySelector(`meta[name="${name}"]`);
  if (!meta) {
    meta = doc.createElement("meta");
    meta.name = name;
    doc.head.appendChild(meta);
  }
  meta.content = content;
}

export function injectPageStylesFromHtml(html, baseUrl, doc = document) {
  if (typeof DOMParser === "undefined" || !doc) {
    return false;
  }

  const parsed = new DOMParser().parseFromString(html, "text/html");
  const base = baseUrl instanceof URL ? baseUrl : new URL(String(baseUrl));

  for (const link of parsed.querySelectorAll('link[rel="stylesheet"][href]')) {
    const href = resolveAssetUrl(link.getAttribute("href"), base);
    ensureHeadLink(doc, href);
  }

  for (const [index, style] of [...parsed.querySelectorAll("head > style")].entries()) {
    ensureHeadStyle(doc, style.textContent ?? "", `inline-${index}`);
  }

  for (const script of parsed.querySelectorAll("head > script:not([src])")) {
    const text = script.textContent ?? "";
    if (!text.includes("matchMedia") && !text.includes("prefers-color-scheme")) {
      continue;
    }
    ensureHeadScript(doc, text, "theme");
  }

  const colorScheme = parsed.querySelector('meta[name="color-scheme"]')?.getAttribute("content");
  if (colorScheme) {
    ensureMeta(doc, "color-scheme", colorScheme);
  }

  return true;
}

export async function injectPageStylesFromHtmlUrl(htmlUrl, fetchFn = fetch, doc = document) {
  if (!htmlUrl) return false;
  const response = await fetchFn(htmlUrl);
  if (!response.ok) return false;
  const html = await response.text();
  return injectPageStylesFromHtml(html, htmlUrl, doc);
}
