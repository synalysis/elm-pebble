/**
 * Array.foldr must transfer ownership of each new accumulator. Releasing the
 * fold result after assign freed list spines (Scene3d Mesh collect* foldrs),
 * so Primitives.sphere/cylinder became EmptyMesh and HeroScene drew ~11 entities.
 */
import { createRcRuntime, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/rc_runtime.js";

const memory = new WebAssembly.Memory({ initial: 1 });
const runtime = createRcRuntime({});
runtime.setMemory(memory);
const view = () => new DataView(memory.buffer);
const scratch = 4096;

const writePtr = (slot, fn, ...args) => {
  const rc = fn(slot, ...args);
  if (rc !== RC_SUCCESS) throw new Error(`rc=${rc} args=${args}`);
  return view().getUint32(slot, true);
};

const listNil = runtime.buildImport("list_nil");
const listCons = runtime.buildImport("list_cons");
const arrayFromList = runtime.buildImport("array_from_list");
const arrayFoldr = runtime.buildImport("array_foldr");
const makeClosure = runtime.buildImport("make_closure");
const newInt = runtime.buildImport("new_int");

const n1 = writePtr(scratch, newInt, 1);
const n2 = writePtr(scratch + 4, newInt, 2);
const n3 = writePtr(scratch + 8, newInt, 3);
const nil = writePtr(scratch + 12, listNil);
const l3 = writePtr(scratch + 16, listCons, n3, nil);
const l2 = writePtr(scratch + 20, listCons, n2, l3);
const l1 = writePtr(scratch + 24, listCons, n1, l2);
const arr = writePtr(scratch + 28, arrayFromList, l1);
const acc0 = writePtr(scratch + 32, listNil);

let consCalls = 0;
runtime.setClosureInvoker((_fnIndex, _captures, args) => {
  consCalls += 1;
  const head = args[0] | 0;
  const tail = args[1] | 0;
  const outSlot = scratch + 128;
  const rc = listCons(outSlot, head, tail);
  if (rc !== RC_SUCCESS) return { rc, value: 0 };
  return { rc: RC_SUCCESS, value: view().getUint32(outSlot, true) };
});

const zeros = Array(12).fill(0);
const clos = writePtr(scratch + 36, makeClosure, 1, 2, ...zeros);

const outSlot = scratch + 40;
const foldRc = arrayFoldr(outSlot, clos, acc0, arr);
if (foldRc !== RC_SUCCESS) {
  console.error("array_foldr rc", foldRc);
  process.exit(1);
}
const result = view().getUint32(outSlot, true);
const payload = runtime.readHandle(result);
const len = payload?.items?.length ?? -1;
const ints = (payload?.items ?? []).map((p) => runtime.readHandle(p)?.value);

if (len !== 3 || consCalls !== 3 || JSON.stringify(ints) !== "[1,2,3]") {
  console.error("array_foldr list rebuild failed", { len, consCalls, ints });
  process.exit(1);
}

console.log(`[array-foldr] ok len=${len} ints=${ints.join(",")} calls=${consCalls}`);
process.exit(0);
