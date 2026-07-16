/**
 * Browser Random.generate for elmc WASM web builds.
 */

export function createRandomRuntime(deps) {
  const {
    RC_SUCCESS,
    allocHandle,
    readHandle,
    writeOut,
    intValue,
    invokeClosure,
    cmdNoneHandle,
    TAG_CMD,
    TAG_RESULT,
    TAG_CLOSURE,
    dispatchPlatformMsg,
    newIntHandle,
  } = deps;

  let seed = (Date.now() ^ (Math.random() * 0x7fffffff)) | 0;

  const nextInt = () => {
    seed = (Math.imul(seed, 1664525) + 1013904223) | 0;
    return seed >>> 0;
  };

  const randomGenerate = (outPtr, toMsgPtr, generatorPtr) => {
    let valuePtr = 0;
    const genPayload = readHandle(generatorPtr | 0);
    if (genPayload?.tag === TAG_CLOSURE) {
      const { rc, value } = invokeClosure(generatorPtr | 0, []);
      if (rc === RC_SUCCESS && value) valuePtr = value | 0;
    }
    if (!valuePtr) {
      valuePtr = newIntHandle(nextInt() & 0x7fffffff);
    }

    const handle = allocHandle({
      tag: TAG_CMD,
      kind: "random_generate",
      toMsg: toMsgPtr | 0,
      value: valuePtr | 0,
    });
    writeOut(outPtr, handle);
    return RC_SUCCESS;
  };

  const drainRandomCommands = (cmdPtr) => {
    const payload = readHandle(cmdPtr);
    if (!payload || payload.tag !== TAG_CMD || payload.kind !== "random_generate") return;

    const valuePtr = payload.value | 0;
    const { rc, value } = invokeClosure(payload.toMsg | 0, [valuePtr]);
    if (rc === RC_SUCCESS && value && dispatchPlatformMsg) {
      dispatchPlatformMsg(value);
    }
  };

  return { randomGenerate, drainRandomCommands, nextInt };
}
