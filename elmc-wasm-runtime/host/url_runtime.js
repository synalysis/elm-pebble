/**
 * Browser URL parsing for Elm Browser.application / Navigation.
 *
 * Url record field order matches elm/url declaration order:
 *   0 protocol, 1 host, 2 port_, 3 path, 4 query, 5 fragment
 *
 * Url.path is a String (e.g. "/wasm"), not a segment list. Protocol tags
 * come from the WASM constructor_tags manifest (Url.Http / Url.Https).
 */

export function createUrlRuntime(deps) {
  const {
    allocHandle,
    newStringHandle,
    newIntHandle,
    stringValue,
    listItems = () => [],
    readHandle = () => null,
    TAG_RECORD,
    TAG_MAYBE,
    TAG_TUPLE2,
    TAG_INT,
    TAG_STRING,
    constructorTags = {},
  } = deps;

  const constructorTag = (qualifiedName, fallback) => {
    if (constructorTags[qualifiedName] != null) {
      return constructorTags[qualifiedName] | 0;
    }
    const short = qualifiedName.split(".").pop();
    if (constructorTags[short] != null) {
      return constructorTags[short] | 0;
    }
    return fallback | 0;
  };

  const urlRequestInternalTag = () =>
    constructorTag("Browser.Internal", constructorTag("Internal", 0));
  const urlRequestExternalTag = () =>
    constructorTag("Browser.External", constructorTag("External", 1));

  const maybeJust = (valuePtr) =>
    allocHandle({ tag: TAG_MAYBE, value: valuePtr | 0, isJust: true });

  const maybeNothing = () => allocHandle({ tag: TAG_MAYBE, value: null });

  const protocolFromString = (proto) => {
    const p = (proto || "").replace(":", "").toLowerCase();
    const tag =
      p === "https"
        ? constructorTag("Url.Https", constructorTag("Https", 2))
        : constructorTag("Url.Http", constructorTag("Http", 1));
    return newIntHandle(tag);
  };

  const pathStringFromLocation = (pathname) => {
    const raw = pathname || "/";
    return raw.startsWith("/") ? raw : `/${raw}`;
  };

  const urlFromParts = ({ protocol, host, port, pathname, search, hash }) => {
    const portMaybe =
      port && port !== "" && port !== "80" && port !== "443"
        ? maybeJust(newIntHandle(Number.parseInt(port, 10) || 0))
        : maybeNothing();
    const queryMaybe =
      search && search.length > 1 ? maybeJust(newStringHandle(search.slice(1))) : maybeNothing();
    const fragmentMaybe =
      hash && hash.length > 1 ? maybeJust(newStringHandle(hash.slice(1))) : maybeNothing();

    return allocHandle({
      tag: TAG_RECORD,
      fields: [
        protocolFromString(protocol),
        newStringHandle(host || "localhost"),
        portMaybe,
        newStringHandle(pathStringFromLocation(pathname)),
        queryMaybe,
        fragmentMaybe,
      ],
    });
  };

  const urlFromLocation = (location) => {
    if (!location) {
      return urlFromParts({
        protocol: "http:",
        host: "localhost",
        port: "",
        pathname: "/",
        search: "",
        hash: "",
      });
    }
    return urlFromParts({
      protocol: location.protocol,
      host: location.hostname,
      port: location.port,
      pathname: location.pathname,
      search: location.search,
      hash: location.hash,
    });
  };

  const intValue = (ptr) => {
    const payload = readHandle(ptr | 0);
    return payload?.tag === TAG_INT ? payload.value | 0 : 0;
  };

  const maybePayloadPtr = (ptr) => {
    const payload = readHandle(ptr | 0);
    if (!payload) return 0;
    if (payload.tag === TAG_MAYBE) {
      if (payload.isJust === false || payload.value == null) return 0;
      return payload.value | 0;
    }
    if (payload.tag === TAG_INT && (payload.value | 0) === 0) return 0;
    if (payload.tag === TAG_TUPLE2) {
      const tag = intValue(payload.first | 0);
      return tag === 0 ? 0 : payload.second | 0;
    }
    return ptr | 0;
  };

  const maybeString = (ptr) => {
    const inner = maybePayloadPtr(ptr);
    return inner ? stringValue(inner) : null;
  };

  const maybeInt = (ptr) => {
    const inner = maybePayloadPtr(ptr);
    return inner ? intValue(inner) : null;
  };

  const protocolHandle = (https) =>
    newIntHandle(
      https
        ? constructorTag("Url.Https", constructorTag("Https", 2))
        : constructorTag("Url.Http", constructorTag("Http", 1))
    );

  const urlRecord = (https, host, port, path, params, frag) =>
    allocHandle({
      tag: TAG_RECORD,
      fields: [
        protocolHandle(https),
        newStringHandle(host),
        port == null ? maybeNothing() : maybeJust(newIntHandle(port | 0)),
        newStringHandle(path),
        params == null ? maybeNothing() : maybeJust(newStringHandle(params)),
        frag == null ? maybeNothing() : maybeJust(newStringHandle(frag)),
      ],
    });

  const chompBeforePath = (https, path, params, frag, str) => {
    if (!str || str.includes("@")) return maybeNothing();
    const first = str.indexOf(":");
    const last = str.lastIndexOf(":");
    if (first < 0) {
      return maybeJust(urlRecord(https, str, null, path, params, frag));
    }
    if (first !== last) return maybeNothing();
    const portStr = str.slice(first + 1);
    if (!/^-?\d+$/.test(portStr)) return maybeNothing();
    return maybeJust(urlRecord(https, str.slice(0, first), Number.parseInt(portStr, 10), path, params, frag));
  };

  const chompBeforeQuery = (https, params, frag, str) => {
    if (!str) return maybeNothing();
    const slash = str.indexOf("/");
    const path = slash < 0 ? "/" : str.slice(slash);
    const authority = slash < 0 ? str : str.slice(0, slash);
    return chompBeforePath(https, path, params, frag, authority);
  };

  const chompBeforeFragment = (https, frag, str) => {
    if (!str) return maybeNothing();
    const q = str.indexOf("?");
    const params = q < 0 ? null : str.slice(q + 1);
    const before = q < 0 ? str : str.slice(0, q);
    return chompBeforeQuery(https, params, frag, before);
  };

  const chompAfterProtocol = (https, str) => {
    if (!str) return maybeNothing();
    const hash = str.indexOf("#");
    const frag = hash < 0 ? null : str.slice(hash + 1);
    const before = hash < 0 ? str : str.slice(0, hash);
    return chompBeforeFragment(https, frag, before);
  };

  // Official elm/url `fromString` (not `new URL()`): only `http://` / `https://`,
  // keep `:443` / `:80`, reject userinfo and empty host.
  const urlFromString = (urlStr) => {
    const raw = String(urlStr ?? "");
    if (raw.startsWith("https://")) return chompAfterProtocol(true, raw.slice(8));
    if (raw.startsWith("http://")) return chompAfterProtocol(false, raw.slice(7));
    return maybeNothing();
  };

  const urlToString = (urlPtr) => {
    const payload = readHandle(urlPtr | 0);
    if (!payload) return "";
    if (payload.tag === TAG_STRING) return stringValue(urlPtr);
    const fields = payload.fields || [];
    const httpsTag = constructorTag("Url.Https", constructorTag("Https", 2));
    const proto = fields[0] ? intValue(fields[0]) : 0;
    const scheme = proto === httpsTag ? "https://" : "http://";
    const host = fields[1] ? stringValue(fields[1]) : "";
    const portNum = fields[2] ? maybeInt(fields[2]) : null;
    const port = portNum == null ? "" : `:${portNum}`;
    const path = fields[3] ? stringValue(fields[3]) : "";
    const query = fields[4] ? maybeString(fields[4]) : null;
    const fragment = fields[5] ? maybeString(fields[5]) : null;
    return (
      scheme +
      host +
      port +
      path +
      (query != null && query !== "" ? `?${query}` : "") +
      (fragment != null && fragment !== "" ? `#${fragment}` : "")
    );
  };

  const joinPath = (listPtr) =>
    (typeof listItems === "function" ? listItems(listPtr) : []).map((p) => stringValue(p)).join("/");

  const queryPair = (ptr) => {
    const payload = readHandle(ptr | 0);
    if (!payload) return "";
    if (payload.tag === TAG_TUPLE2) {
      const first = readHandle(payload.first | 0);
      if (first?.tag === TAG_INT) {
        const inner = readHandle(payload.second | 0);
        if (inner?.tag === TAG_TUPLE2) {
          return `${stringValue(inner.first)}=${stringValue(inner.second)}`;
        }
        return `${stringValue(payload.second)}=`;
      }
      return `${stringValue(payload.first)}=${stringValue(payload.second)}`;
    }
    if (payload.tag === TAG_RECORD && Array.isArray(payload.fields) && payload.fields.length >= 2) {
      return `${stringValue(payload.fields[0])}=${stringValue(payload.fields[1])}`;
    }
    return "";
  };

  const toQuery = (listPtr) => {
    const pairs = (typeof listItems === "function" ? listItems(listPtr) : [])
      .map(queryPair)
      .filter((pair) => pair.length > 0);
    return pairs.length ? `?${pairs.join("&")}` : "";
  };

  const urlBuilderAbsolute = (pathPtr, queryPtr) => `/${joinPath(pathPtr)}${toQuery(queryPtr)}`;

  const urlBuilderRelative = (pathPtr, queryPtr) => `${joinPath(pathPtr)}${toQuery(queryPtr)}`;

  const urlBuilderCrossOrigin = (prePathPtr, pathPtr, queryPtr) =>
    `${stringValue(prePathPtr)}/${joinPath(pathPtr)}${toQuery(queryPtr)}`;

  const rootPrePath = (rootPtr) => {
    const payload = readHandle(rootPtr | 0);
    // Official `type Root = Absolute | Relative | CrossOrigin String`.
    // Mixed unions store nullary Absolute/Relative as tuple2(tag, ()); only
    // CrossOrigin carries a String payload. Treating every tuple2 as
    // CrossOrigin prepended "/" onto official `custom Relative`.
    const relTag = constructorTag("Url.Builder.Relative", constructorTag("Relative", 2));
    if (!payload) return "/";
    if (payload.tag === TAG_INT) {
      return intValue(rootPtr) === relTag ? "" : "/";
    }
    if (payload.tag === TAG_TUPLE2) {
      const second = readHandle(payload.second | 0);
      if (second?.tag === TAG_STRING) {
        return `${stringValue(payload.second)}/`;
      }
      return intValue(payload.first | 0) === relTag ? "" : "/";
    }
    if (payload.tag === TAG_RECORD && payload.fields?.length) {
      const field0 = readHandle(payload.fields[0] | 0);
      if (field0?.tag === TAG_STRING) {
        return `${stringValue(payload.fields[0])}/`;
      }
    }
    return "/";
  };

  const urlBuilderCustom = (rootPtr, pathPtr, queryPtr, fragmentPtr) => {
    const fragmentless = `${rootPrePath(rootPtr)}${joinPath(pathPtr)}${toQuery(queryPtr)}`;
    const fragment = maybeString(fragmentPtr);
    return fragment == null ? fragmentless : `${fragmentless}#${fragment}`;
  };

  const urlBuilderQueryString = (keyPtr, valuePtr) =>
    allocHandle({
      tag: TAG_TUPLE2,
      first: newStringHandle(encodeURIComponent(stringValue(keyPtr))),
      second: newStringHandle(encodeURIComponent(stringValue(valuePtr))),
    });

  const urlBuilderQueryInt = (keyPtr, valuePtr) =>
    allocHandle({
      tag: TAG_TUPLE2,
      first: newStringHandle(encodeURIComponent(stringValue(keyPtr))),
      second: newStringHandle(String(intValue(valuePtr))),
    });

  /** UrlRequest = Internal Url | External String (constructor tags from manifest) */
  const urlRequestInternal = (urlPtr) =>
    allocHandle({
      tag: TAG_TUPLE2,
      first: newIntHandle(urlRequestInternalTag()),
      second: urlPtr | 0,
    });

  const urlRequestExternal = (urlPtr) =>
    allocHandle({
      tag: TAG_TUPLE2,
      first: newIntHandle(urlRequestExternalTag()),
      second: urlPtr | 0,
    });

  const normalizePath = (pathname) => {
    const raw = pathname || "/";
    if (raw === "/") return "/";
    return raw.endsWith("/") && raw.length > 1 ? raw.slice(0, -1) : raw;
  };

  return {
    urlFromLocation,
    urlFromString,
    urlToString,
    urlFromParts,
    urlBuilderAbsolute,
    urlBuilderRelative,
    urlBuilderCrossOrigin,
    urlBuilderCustom,
    urlBuilderQueryString,
    urlBuilderQueryInt,
    urlBuilderToQuery: toQuery,
    urlRequestInternal,
    urlRequestExternal,
    normalizePath,
    pathStringFromLocation,
    stringValue,
    maybeJust,
    maybeNothing,
    newStringHandle,
  };
}
