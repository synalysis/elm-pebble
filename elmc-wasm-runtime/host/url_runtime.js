/**
 * Browser URL parsing for Elm Browser.application / Navigation.
 *
 * Elm Url record: protocol, host, port_, path, query, fragment
 * Protocol: Http = 0, Https = 1 (Elm.Kernel.Url tags)
 */

export function createUrlRuntime(deps) {
  const {
    allocHandle,
    newStringHandle,
    newIntHandle,
    stringValue,
    TAG_RECORD,
    TAG_MAYBE,
    TAG_TUPLE2,
    TAG_INT,
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

  const pathFromSegments = (pathname) => {
    const raw = pathname || "/";
    if (raw === "/") return 0;
    const parts = raw.split("/").filter((s) => s !== "");
    if (parts.length === 0) return 0;
    let list = 0;
    for (let i = parts.length - 1; i >= 0; i--) {
      const seg = newStringHandle(parts[i]);
      list = allocHandle({ tag: TAG_TUPLE2, first: seg, second: list | 0 });
    }
    return list;
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
    const queryMaybe = search && search.length > 1 ? maybeJust(newStringHandle(search.slice(1))) : maybeNothing();
    const fragmentMaybe = hash && hash.length > 1 ? maybeJust(newStringHandle(hash.slice(1))) : maybeNothing();

    return allocHandle({
      tag: TAG_RECORD,
      fields: [
        protocolFromString(protocol),
        newStringHandle(host || "localhost"),
        portMaybe,
        pathFromSegments(pathname),
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

  const urlFromString = (urlStr) => {
    try {
      if (typeof URL !== "undefined") {
        const parsed = new URL(urlStr, "http://localhost");
        return urlFromParts({
          protocol: parsed.protocol,
          host: parsed.hostname,
          port: parsed.port,
          pathname: parsed.pathname,
          search: parsed.search,
          hash: parsed.hash,
        });
      }
    } catch (_err) {
      /* fall through */
    }
    return urlFromParts({
      protocol: "http:",
      host: "localhost",
      port: "",
      pathname: urlStr?.startsWith("/") ? urlStr : `/${urlStr || ""}`,
      search: "",
      hash: "",
    });
  };

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
    urlFromParts,
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
