/**
 * Elm.Kernel.Regex host helpers for WASM web builds.
 *
 * Official elm/regex: fromStringWith is Maybe Regex; findAtMost / split /
 * replaceAtMost take an optional limit (n <= 0 means unlimited except split,
 * where n <= 0 returns the original string as a singleton list).
 */

export function createRegexRuntime(deps) {
  const {
    RC_SUCCESS,
    writeOut,
    stringValue,
    maybeJustOwn,
    maybeNothing,
    newStringHandle,
    newIntHandle,
    readHandle,
    newList,
    resultOk,
    resultErr,
    invokeClosure,
    TAG_STRING,
    TAG_RECORD,
    TAG_INT,
    TAG_CLOSURE,
    TAG_MAYBE,
    allocHandle,
  } = deps;

  const boolValue = (ptr) => {
    const payload = readHandle(ptr | 0);
    if (!payload) return false;
    if (payload.tag === TAG_INT) return (payload.value | 0) !== 0;
    return Boolean(payload.value);
  };

  const intValue = (ptr) => {
    const payload = readHandle(ptr | 0);
    return payload?.tag === TAG_INT ? payload.value | 0 : 0;
  };

  const regexFromRecord = (ptr) => {
    const payload = readHandle(ptr | 0);
    if (payload?.tag === TAG_STRING) {
      try {
        return new RegExp(payload.value, "g");
      } catch (_err) {
        return null;
      }
    }
    if (payload?.elmRegex) return payload.elmRegex;
    if (payload?.tag === TAG_RECORD && payload.fields?.[0]) {
      const source = stringValue(payload.fields[0] | 0);
      const flags = payload.fields[1] ? stringValue(payload.fields[1] | 0) : "g";
      if (source) {
        try {
          return new RegExp(source, flags || "g");
        } catch (_err) {
          return null;
        }
      }
    }
    return null;
  };

  const wrapRegex = (re) =>
    allocHandle({
      tag: TAG_RECORD,
      elmRegex: re,
      fields: [newStringHandle(re.source), newStringHandle(re.flags || "g")],
    });

  const globalCopy = (re) => {
    if (!re) return null;
    const flags = re.flags.includes("g") ? re.flags : `${re.flags}g`;
    return new RegExp(re.source, flags);
  };

  const maybeNothingHandle = () => {
    if (typeof maybeNothing === "function") {
      // maybeNothing writes through an out pointer in some hosts; prefer a handle.
    }
    return allocHandle({ tag: TAG_MAYBE, value: null, isJust: false });
  };

  const maybeJustHandle = (valuePtr) =>
    allocHandle({ tag: TAG_MAYBE, value: valuePtr | 0, isJust: true });

  const matchRecord = (match, number) => {
    const submatches = match.slice(1).map((s) =>
      s == null ? maybeNothingHandle() : maybeJustHandle(newStringHandle(s))
    );
    // Elm stores record fields alphabetically: index, match, number, submatches.
    return allocHandle({
      tag: TAG_RECORD,
      fields: [
        newIntHandle(match.index | 0),
        newStringHandle(match[0] ?? ""),
        newIntHandle(number | 0),
        newList(submatches),
      ],
    });
  };

  const regexFromStringWith = (outPtr, optionsPtr, patternPtr) => {
    const pattern = stringValue(patternPtr | 0) ?? "";
    const options = readHandle(optionsPtr | 0);
    const fields = options?.fields || [];
    const caseInsensitive = fields[0] ? boolValue(fields[0]) : false;
    const multiline = fields[1] ? boolValue(fields[1]) : false;
    let flags = "g";
    if (multiline) flags += "m";
    if (caseInsensitive) flags += "i";
    try {
      const re = new RegExp(pattern, flags);
      if (typeof maybeJustOwn === "function") {
        return maybeJustOwn(outPtr, wrapRegex(re));
      }
      writeOut(outPtr, maybeJustHandle(wrapRegex(re)));
      return RC_SUCCESS;
    } catch (_err) {
      if (typeof maybeNothing === "function") {
        return maybeNothing(outPtr);
      }
      writeOut(outPtr, maybeNothingHandle());
      return RC_SUCCESS;
    }
  };

  const regexFromString = (outPtr, patternPtr) => {
    const options = allocHandle({
      tag: TAG_RECORD,
      fields: [newIntHandle(0), newIntHandle(0)],
    });
    return regexFromStringWith(outPtr, options, patternPtr);
  };

  const findMatches = (re, haystack, limit) => {
    const global = globalCopy(re);
    if (!global) return [];
    const out = [];
    let number = 1;
    let match = global.exec(haystack);
    while (match) {
      out.push(matchRecord(match, number));
      number += 1;
      if (match[0].length === 0) global.lastIndex += 1;
      if (limit > 0 && out.length >= limit) break;
      match = global.exec(haystack);
    }
    return out;
  };

  const regexFind = (outPtr, regexPtr, stringPtr) => {
    const re = regexFromRecord(regexPtr);
    const haystack = stringValue(stringPtr | 0) ?? "";
    writeOut(outPtr, newList(findMatches(re, haystack, 0)));
    return RC_SUCCESS;
  };

  const regexFindAtMost = (outPtr, nPtr, regexPtr, stringPtr) => {
    const re = regexFromRecord(regexPtr);
    const haystack = stringValue(stringPtr | 0) ?? "";
    const limit = intValue(nPtr);
    writeOut(outPtr, newList(findMatches(re, haystack, limit)));
    return RC_SUCCESS;
  };

  const regexNever = (outPtr) => {
    // Official elm/regex kernel never is a RegExp that matches nothing (`/a^/`).
    writeOut(outPtr, wrapRegex(new RegExp("a^")));
    return RC_SUCCESS;
  };

  const regexContains = (outPtr, regexPtr, stringPtr) => {
    const re = regexFromRecord(regexPtr);
    const haystack = stringValue(stringPtr | 0) ?? "";
    // Official contains does not consume a shared `g` lastIndex.
    const found = re ? new RegExp(re.source, re.flags).test(haystack) : false;
    writeOut(outPtr, newIntHandle(found ? 1 : 0));
    return RC_SUCCESS;
  };

  const applyReplacer = (replacerPtr, match, number) => {
    const payload = readHandle(replacerPtr | 0);
    if (payload?.tag === TAG_CLOSURE && typeof invokeClosure === "function") {
      const rec = matchRecord(match, number);
      const result = invokeClosure(replacerPtr, [rec]);
      return stringValue(result?.value ?? 0);
    }
    return stringValue(replacerPtr | 0) ?? "";
  };

  const replaceLimited = (re, replacerPtr, haystack, limit) => {
    const global = globalCopy(re);
    if (!global) return haystack;
    if (limit === 1 && !re.flags.includes("g")) {
      return haystack.replace(re, (...args) => {
        const raw = args.slice(0, -2);
        raw.index = args[args.length - 2];
        return applyReplacer(replacerPtr, raw, 1);
      });
    }
    let count = 0;
    return haystack.replace(global, (...args) => {
      count += 1;
      if (limit > 0 && count > limit) return args[0];
      const raw = args.slice(0, -2);
      raw.index = args[args.length - 2];
      return applyReplacer(replacerPtr, raw, count);
    });
  };

  const regexReplace = (outPtr, regexPtr, replacementPtr, stringPtr) => {
    const re = regexFromRecord(regexPtr);
    const haystack = stringValue(stringPtr | 0) ?? "";
    const next = re ? replaceLimited(re, replacementPtr, haystack, 0) : haystack;
    writeOut(outPtr, newStringHandle(next));
    return RC_SUCCESS;
  };

  const regexReplaceAtMost = (outPtr, nPtr, regexPtr, replacementPtr, stringPtr) => {
    const re = regexFromRecord(regexPtr);
    const haystack = stringValue(stringPtr | 0) ?? "";
    const next = re ? replaceLimited(re, replacementPtr, haystack, intValue(nPtr)) : haystack;
    writeOut(outPtr, newStringHandle(next));
    return RC_SUCCESS;
  };

  const splitLimited = (re, haystack, limit) => {
    if (limit === 0) return [newStringHandle(haystack)];
    const global = globalCopy(re);
    if (!global) return [newStringHandle(haystack)];
    const parts = [];
    let last = 0;
    let count = 0;
    let match = global.exec(haystack);
    while (match) {
      if (limit > 0 && count >= limit) break;
      parts.push(newStringHandle(haystack.slice(last, match.index)));
      last = match.index + match[0].length;
      count += 1;
      if (match[0].length === 0) global.lastIndex += 1;
      match = global.exec(haystack);
    }
    parts.push(newStringHandle(haystack.slice(last)));
    return parts;
  };

  const regexSplit = (outPtr, regexPtr, stringPtr) => {
    const re = regexFromRecord(regexPtr);
    const haystack = stringValue(stringPtr | 0) ?? "";
    writeOut(outPtr, newList(splitLimited(re, haystack, -1)));
    return RC_SUCCESS;
  };

  const regexSplitAtMost = (outPtr, nPtr, regexPtr, stringPtr) => {
    const re = regexFromRecord(regexPtr);
    const haystack = stringValue(stringPtr | 0) ?? "";
    writeOut(outPtr, newList(splitLimited(re, haystack, intValue(nPtr))));
    return RC_SUCCESS;
  };

  return {
    regexFromString,
    regexFromStringWith,
    regexFind,
    regexFindAtMost,
    regexNever,
    regexContains,
    regexReplace,
    regexReplaceAtMost,
    regexSplit,
    regexSplitAtMost,
  };
}
