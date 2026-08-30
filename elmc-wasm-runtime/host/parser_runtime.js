/**
 * Elm.Kernel.Parser host helpers for WASM web builds.
 *
 * kind 1: isSubString(small, offset, row, col, big) -> (offset| -1, row, col)
 * kind 2: isSubChar(predicate, offset, string) -> newOffset
 *   (-1 no match, -2 matched newline, else next offset)
 * kind 3: isAsciiCode(code, offset, string) -> Bool
 * kind 4: chompBase10(offset, string) -> newOffset
 * kind 5: consumeBase(base, offset, string) -> (offset, total)
 * kind 6: consumeBase16(offset, string) -> (offset, total)
 * kind 7: findSubString(small, offset, row, col, big) -> (index| -1, row, col)
 */

export function createParserRuntime(deps) {
  const {
    RC_SUCCESS,
    RC_ERR_UNIMPLEMENTED,
    writeOut,
    intValue,
    newIntHandle,
    newCharHandle,
    invokeClosure,
    tuple2,
    stringValue,
  } = deps;

  const asHandle = (ptr) => ptr | 0;

  function parserCmd(outPtr, kind, ...params) {
    try {
      if ((kind | 0) === 1) return isSubString(outPtr, params);
      if ((kind | 0) === 2) return isSubChar(outPtr, params);
      if ((kind | 0) === 3) return isAsciiCode(outPtr, params);
      if ((kind | 0) === 4) return chompBase10(outPtr, params);
      if ((kind | 0) === 5) return consumeBase(outPtr, params);
      if ((kind | 0) === 6) return consumeBase16(outPtr, params);
      if ((kind | 0) === 7) return findSubString(outPtr, params);
      console.warn("[elmc-wasm-runtime] parser_cmd unimplemented kind", kind, { params });
      return RC_ERR_UNIMPLEMENTED;
    } catch (err) {
      console.error("[elmc-wasm-runtime] parser_cmd failed", err);
      return RC_ERR_UNIMPLEMENTED;
    }
  }

  function isSubString(outPtr, params) {
    const [smallPtr, offsetPtr, rowPtr, colPtr, bigPtr] = params;
    const small = stringValue(asHandle(smallPtr)) ?? "";
    const big = stringValue(asHandle(bigPtr)) ?? "";
    let offset = intValue(asHandle(offsetPtr)) | 0;
    let row = intValue(asHandle(rowPtr)) | 0;
    let col = intValue(asHandle(colPtr)) | 0;

    const smallLength = small.length;
    let isGood = offset + smallLength <= big.length;
    let i = 0;

    while (isGood && i < smallLength) {
      const code = big.charCodeAt(offset);
      isGood =
        small[i++] === big[offset++] &&
        (code === 0x000a
          ? ((row += 1), (col = 1), true)
          : ((col += 1),
            (code & 0xf800) === 0xd800 ? small[i++] === big[offset++] : true));
    }

    const newOffset = isGood ? offset : -1;
    // Elm 3-tuples are nested Tuple2: (a, b, c) => (a, (b, c))
    const result = tuple2(
      newIntHandle(newOffset),
      tuple2(newIntHandle(row), newIntHandle(col))
    );
    writeOut(outPtr, result);
    return RC_SUCCESS;
  }

  function isSubChar(outPtr, params) {
    const [predPtr, offsetPtr, stringPtr] = params;
    const string = stringValue(asHandle(stringPtr)) ?? "";
    const offset = intValue(asHandle(offsetPtr)) | 0;

    if (string.length <= offset) {
      writeOut(outPtr, newIntHandle(-1));
      return RC_SUCCESS;
    }

    const code = string.charCodeAt(offset);
    const isSurrogate = (code & 0xf800) === 0xd800;
    const cp = string.codePointAt(offset);
    const { rc, value } = invokeClosure(asHandle(predPtr), [newCharHandle(cp)]);
    if (rc !== 0) return rc || RC_ERR_UNIMPLEMENTED;

    const ok = intValue(value) !== 0;
    if (!ok) {
      writeOut(outPtr, newIntHandle(-1));
      return RC_SUCCESS;
    }

    if (isSurrogate) {
      writeOut(outPtr, newIntHandle(offset + 2));
      return RC_SUCCESS;
    }

    writeOut(outPtr, newIntHandle(string[offset] === "\n" ? -2 : offset + 1));
    return RC_SUCCESS;
  }

  function isAsciiCode(outPtr, params) {
    const [codePtr, offsetPtr, stringPtr] = params;
    const string = stringValue(asHandle(stringPtr)) ?? "";
    const offset = intValue(asHandle(offsetPtr)) | 0;
    const code = intValue(asHandle(codePtr)) | 0;
    writeOut(outPtr, newIntHandle(string.charCodeAt(offset) === code ? 1 : 0));
    return RC_SUCCESS;
  }

  function chompBase10(outPtr, params) {
    const [offsetPtr, stringPtr] = params;
    const string = stringValue(asHandle(stringPtr)) ?? "";
    let offset = intValue(asHandle(offsetPtr)) | 0;
    for (; offset < string.length; offset++) {
      const code = string.charCodeAt(offset);
      if (code < 0x30 || 0x39 < code) break;
    }
    writeOut(outPtr, newIntHandle(offset));
    return RC_SUCCESS;
  }

  function consumeBase(outPtr, params) {
    const [basePtr, offsetPtr, stringPtr] = params;
    const string = stringValue(asHandle(stringPtr)) ?? "";
    const base = intValue(asHandle(basePtr)) | 0;
    let offset = intValue(asHandle(offsetPtr)) | 0;
    let total = 0;
    for (; offset < string.length; offset++) {
      const digit = string.charCodeAt(offset) - 0x30;
      if (digit < 0 || base <= digit) break;
      total = base * total + digit;
    }
    writeOut(outPtr, tuple2(newIntHandle(offset), newIntHandle(total)));
    return RC_SUCCESS;
  }

  function consumeBase16(outPtr, params) {
    const [offsetPtr, stringPtr] = params;
    const string = stringValue(asHandle(stringPtr)) ?? "";
    let offset = intValue(asHandle(offsetPtr)) | 0;
    let total = 0;
    for (; offset < string.length; offset++) {
      const code = string.charCodeAt(offset);
      if (0x30 <= code && code <= 0x39) {
        total = 16 * total + code - 0x30;
      } else if (0x41 <= code && code <= 0x46) {
        total = 16 * total + code - 55;
      } else if (0x61 <= code && code <= 0x66) {
        total = 16 * total + code - 87;
      } else {
        break;
      }
    }
    writeOut(outPtr, tuple2(newIntHandle(offset), newIntHandle(total)));
    return RC_SUCCESS;
  }

  function findSubString(outPtr, params) {
    const [smallPtr, offsetPtr, rowPtr, colPtr, bigPtr] = params;
    const small = stringValue(asHandle(smallPtr)) ?? "";
    const big = stringValue(asHandle(bigPtr)) ?? "";
    let offset = intValue(asHandle(offsetPtr)) | 0;
    let row = intValue(asHandle(rowPtr)) | 0;
    let col = intValue(asHandle(colPtr)) | 0;
    const newOffset = big.indexOf(small, offset);
    const target = newOffset < 0 ? big.length : newOffset + small.length;

    while (offset < target) {
      const code = big.charCodeAt(offset++);
      if (code === 0x000a) {
        col = 1;
        row += 1;
      } else {
        col += 1;
        if ((code & 0xf800) === 0xd800) offset += 1;
      }
    }

    writeOut(
      outPtr,
      tuple2(newIntHandle(newOffset), tuple2(newIntHandle(row), newIntHandle(col)))
    );
    return RC_SUCCESS;
  }

  return { parserCmd };
}
