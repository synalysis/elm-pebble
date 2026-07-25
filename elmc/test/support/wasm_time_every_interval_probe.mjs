/**
 * Time.every interval ABI: raw i32 ms, or boxed TAG_FLOAT (4).
 * Must not treat raw N as INT handle id N (collision → ~2ms → CPU peg).
 */
import { createRcRuntime, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/rc_runtime.js";

const TAG_INT = 1;
const TAG_FLOAT = 4;

const memory = new WebAssembly.Memory({ initial: 1 });
const runtime = createRcRuntime({});
runtime.setMemory(memory);
const view = () => new DataView(memory.buffer);
const scratch = 4096;

const writePtr = (slot, fn, ...args) => {
  const rc = fn(slot, ...args);
  if (rc !== RC_SUCCESS) throw new Error(`rc=${rc}`);
  return view().getUint32(slot, true);
};

const newFloat = runtime.buildImport("new_float");
const newInt = runtime.buildImport("new_int");

const buf = new ArrayBuffer(4);
new DataView(buf).setFloat32(0, 64, true);
const bits = new DataView(buf).getUint32(0, true);
const floatPtr = writePtr(scratch, newFloat, bits);
if (runtime.readHandle(floatPtr)?.tag !== TAG_FLOAT) {
  console.error(`expected TAG_FLOAT at ${floatPtr}`);
  process.exit(1);
}

const collideId = writePtr(scratch + 4, newInt, 2);
const collidePayload = runtime.readHandle(collideId);
if (collidePayload?.tag !== TAG_INT || (collidePayload.value | 0) !== 2) {
  console.error("expected INT(2) collide handle", collideId, collidePayload);
  process.exit(1);
}

const decode = runtime.timeEveryIntervalMs;
if (typeof decode !== "function") {
  console.error("runtime.timeEveryIntervalMs missing");
  process.exit(1);
}

const decodedFloat = decode(floatPtr);
const decodedRaw = decode(collideId);
const buggyAsInt = collidePayload.value | 0;

if (decodedFloat !== 64) {
  console.error(`expected float interval 64, got ${decodedFloat}`);
  process.exit(1);
}
if (decodedRaw !== collideId) {
  console.error(
    `expected raw collision interval ${collideId}, got ${decodedRaw} (buggy would be ${buggyAsInt})`
  );
  process.exit(1);
}
if (decodedRaw === buggyAsInt) {
  console.error("collision decode matched buggy asInt path");
  process.exit(1);
}

console.log(
  `[time-every-interval] ok float=${decodedFloat} rawCollide=${decodedRaw} buggyWould=${buggyAsInt} floatHandle=${floatPtr}`
);
process.exit(0);
