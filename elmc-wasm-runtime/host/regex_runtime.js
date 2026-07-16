/**
 * Elm.Kernel.Regex host helpers for WASM web builds.
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
    TAG_STRING,
    TAG_RECORD,
    allocHandle,
  } = deps;

  const regexFromRecord = (ptr) => {
    const payload = readHandle(ptr | 0);
    if (payload?.tag === TAG_STRING) return new RegExp(payload.value);
    if (payload?.tag === TAG_RECORD && payload.fields?.[0]) {
      const source = stringValue(payload.fields[0] | 0);
      if (source) return new RegExp(source);
    }
    return null;
  };

  const wrapRegex = (re) =>
    allocHandle({
      tag: TAG_RECORD,
      fields: [newStringHandle(re.source)],
    });

  const regexFromString = (outPtr, patternPtr) => {
    const pattern = stringValue(patternPtr | 0) ?? "";
    try {
      const re = new RegExp(pattern);
      writeOut(outPtr, resultOk(wrapRegex(re)));
    } catch (err) {
      writeOut(outPtr, resultErr(newStringHandle(String(err?.message || "bad regex"))));
    }
    return RC_SUCCESS;
  };

  const regexFind = (outPtr, regexPtr, stringPtr) => {
    const re = regexFromRecord(regexPtr);
    const haystack = stringValue(stringPtr | 0) ?? "";
    if (!re) return maybeNothing(outPtr);

    const match = re.exec(haystack);
    if (!match) return maybeNothing(outPtr);

    const submatches = match.slice(1).map((s) => newStringHandle(s ?? ""));
    const record = allocHandle({
      tag: TAG_RECORD,
      fields: [
        newStringHandle(match[0] ?? ""),
        newIntHandle(match.index | 0),
        newList(submatches),
      ],
    });
    return maybeJustOwn(outPtr, record);
  };

  const regexContains = (outPtr, regexPtr, stringPtr) => {
    const re = regexFromRecord(regexPtr);
    const haystack = stringValue(stringPtr | 0) ?? "";
    const found = re ? re.test(haystack) : false;
    writeOut(outPtr, newIntHandle(found ? 1 : 0));
    return RC_SUCCESS;
  };

  const regexReplace = (outPtr, regexPtr, replacementPtr, stringPtr) => {
    const re = regexFromRecord(regexPtr);
    const replacement = stringValue(replacementPtr | 0) ?? "";
    const haystack = stringValue(stringPtr | 0) ?? "";
    const next = re ? haystack.replace(re, replacement) : haystack;
    writeOut(outPtr, newStringHandle(next));
    return RC_SUCCESS;
  };

  return {
    regexFromString,
    regexFind,
    regexContains,
    regexReplace,
  };
}
