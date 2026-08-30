/**
 * Browser Random.generate for elmc WASM web builds.
 *
 * Official elm/random: `Generator a = Generator (Seed -> (a, Seed))` and
 * `Seed = Seed state increment`. generate steps that function with a PCG seed
 * (same `initialSeed` math as Random.elm) and sends the value through toMsg.
 */

export function createRandomRuntime(deps) {
  const {
    RC_SUCCESS,
    allocHandle,
    readHandle,
    writeOut,
    invokeClosure,
    cmdNoneHandle,
    TAG_CMD,
    TAG_CLOSURE,
    TAG_TUPLE2 = 6,
    TAG_RECORD = 3,
    newIntHandle,
    dispatchPlatformMsg,
    constructorTags = {},
    retain = null,
    release = null,
  } = deps;

  let seed = (Date.now() ^ (Math.random() * 0x7fffffff)) | 0;
  let liveSeedPtr = 0;

  const nextInt = () => {
    seed = (Math.imul(seed, 1664525) + 1013904223) | 0;
    return seed >>> 0;
  };

  const u32 = (n) => n >>> 0;

  // Official `next (Seed state0 incr)` — Numerical Recipes LCG, unsigned 32-bit.
  const nextState = (state0, incr) => u32(Math.imul(state0, 1664525) + incr);

  const seedCtorTag = () =>
    constructorTags["Random.Seed"] ?? constructorTags["Seed"] ?? 1;

  const makeSeed = (state, incr) => {
    const pair = allocHandle({
      tag: TAG_TUPLE2,
      first: newIntHandle(state | 0),
      second: newIntHandle(incr | 0),
    });
    return allocHandle({
      tag: TAG_TUPLE2,
      first: newIntHandle(seedCtorTag()),
      second: pair,
    });
  };

  // Official `initialSeed x`.
  const initialSeed = (x) => {
    const incr = 1013904223;
    const state1 = nextState(0, incr);
    const state2 = u32(state1 + (x | 0));
    return makeSeed(nextState(state2, incr), incr);
  };

  const currentSeed = () => {
    if (!liveSeedPtr) {
      liveSeedPtr = initialSeed((Date.now() ^ nextInt()) | 0);
      if (retain && liveSeedPtr) retain(null, liveSeedPtr);
    }
    return liveSeedPtr;
  };

  const storeSeed = (nextPtr) => {
    const next = nextPtr | 0;
    if (next === liveSeedPtr) return;
    if (next && retain) retain(null, next);
    if (liveSeedPtr && release) release(liveSeedPtr);
    liveSeedPtr = next;
  };

  const peelGeneratorFn = (ptr) => {
    const seen = new Set();
    let cur = ptr | 0;
    for (let depth = 0; cur && depth < 4; depth++) {
      if (seen.has(cur)) break;
      seen.add(cur);
      const payload = readHandle(cur);
      if (!payload) break;
      if (payload.tag === TAG_CLOSURE) return cur;
      if (payload.tag === TAG_TUPLE2) {
        const second = payload.second | 0;
        if (readHandle(second)?.tag === TAG_CLOSURE) return second;
        const first = payload.first | 0;
        if (readHandle(first)?.tag === TAG_CLOSURE) return first;
        cur = second;
        continue;
      }
      if (payload.tag === TAG_RECORD) {
        for (const field of payload.fields ?? []) {
          if (readHandle(field)?.tag === TAG_CLOSURE) return field | 0;
        }
      }
      break;
    }
    return 0;
  };

  const stepGenerator = (generatorPtr) => {
    const fnPtr = peelGeneratorFn(generatorPtr);
    if (!fnPtr) return 0;
    const seedPtr = currentSeed();
    let { rc, value } = invokeClosure(fnPtr, [seedPtr]);
    if (rc !== RC_SUCCESS || !value) return 0;
    if (readHandle(value)?.tag === TAG_CLOSURE) {
      const next = invokeClosure(value, [seedPtr]);
      if (next.rc !== RC_SUCCESS || !next.value) return 0;
      value = next.value;
    }
    const out = readHandle(value);
    if (out?.tag === TAG_TUPLE2) {
      storeSeed(out.second | 0);
      return out.first | 0;
    }
    return value | 0;
  };

  const randomGenerate = (outPtr, toMsgPtr, generatorPtr) => {
    const valuePtr = stepGenerator(generatorPtr);
    if (!valuePtr) {
      writeOut(outPtr, cmdNoneHandle());
      return RC_SUCCESS;
    }

    if (retain) {
      if (toMsgPtr) retain(null, toMsgPtr | 0);
      retain(null, valuePtr);
    }

    writeOut(
      outPtr,
      allocHandle({
        tag: TAG_CMD,
        kind: "random_generate",
        toMsg: toMsgPtr | 0,
        value: valuePtr | 0,
      })
    );
    return RC_SUCCESS;
  };

  const drainRandomCommands = (cmdPtr, taggers = []) => {
    const payload = readHandle(cmdPtr);
    if (!payload || payload.tag !== TAG_CMD || payload.kind !== "random_generate") return;

    const valuePtr = payload.value | 0;
    const { rc, value } = invokeClosure(payload.toMsg | 0, [valuePtr]);
    if (rc !== RC_SUCCESS || !value || !dispatchPlatformMsg) return;
    let ptr = value | 0;
    for (const taggerPtr of taggers ?? []) {
      if (!taggerPtr) continue;
      const next = invokeClosure(taggerPtr | 0, [ptr]);
      if (next.rc !== RC_SUCCESS) return;
      ptr = next.value | 0;
    }
    if (ptr) dispatchPlatformMsg(ptr);
  };

  return { randomGenerate, drainRandomCommands, nextInt };
}
