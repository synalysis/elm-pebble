/**
 * Regression: over-releasing a list that is still stored as Group.second (or any
 * live tuple/record field) must heal RC instead of leaving a dangling pointer.
 *
 * Mirrors the HeroScene bug where getViewBounds epilogues freed Scene3d.Group
 * child lists while the Group handle remained live for collectRenderPasses.
 */
import { createRcRuntime, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/rc_runtime.js";

const memory = new WebAssembly.Memory({ initial: 1 });
const runtime = createRcRuntime({});
runtime.setMemory(memory);

const view = () => new DataView(memory.buffer);
const scratch = 4096;

const listNil = runtime.buildImport("list_nil");
const listCons = runtime.buildImport("list_cons");
const tuple2 = runtime.buildImport("tuple2");
const release = runtime.buildImport("release");

const writePtr = (slot, fn, ...args) => {
  const rc = fn(slot, ...args);
  if (rc !== RC_SUCCESS) throw new Error(`rc=${rc}`);
  return view().getUint32(slot, true);
};

const empty = writePtr(scratch, listNil);
const item = writePtr(scratch + 4, runtime.buildImport("new_int"), 42);
const list = writePtr(scratch + 8, listCons, item, empty);
const tag = writePtr(scratch + 12, runtime.buildImport("new_int"), 6);
const group = writePtr(scratch + 16, tuple2, tag, list);

const groupPayload = runtime.readHandle(group);
if (!groupPayload || groupPayload.tag !== 6) {
  console.error("expected TAG_TUPLE2 group", groupPayload);
  process.exit(1);
}

const listBefore = runtime.readHandle(list);
if (!listBefore || listBefore.tag !== 2 || (listBefore.items?.length ?? 0) !== 1) {
  console.error("expected list with 1 item before over-release", listBefore);
  process.exit(1);
}

const startRc = listBefore.rc | 0;
// Over-release past the Group's ownership retain — without heal, list is deleted
// while group.second still points at it.
for (let i = 0; i < startRc + 3; i++) {
  release(list);
}

const listAfter = runtime.readHandle(list);
const viaGroup = runtime.readHandle(groupPayload.second | 0);
if (!listAfter || listAfter.tag !== 2) {
  console.error("list handle was freed despite live Group owner", { listAfter, viaGroup });
  process.exit(1);
}
if (!viaGroup || viaGroup.tag !== 2 || (viaGroup.items?.length ?? 0) !== 1) {
  console.error("Group.second dangling after over-release", { viaGroup, listAfter });
  process.exit(1);
}

console.log(
  `[rc-owner-heal] ok listRc=${listAfter.rc} items=${listAfter.items.length} viaGroupItems=${viaGroup.items.length}`
);
process.exit(0);
