/**
 * Record-encoded (tag, payload) unions must match TAG_TUPLE2 for
 * union_tag_as_int / tuple_proj (Effect.Cmd / Cmd.batch host layout).
 */
import { createRcRuntime, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/rc_runtime.js";

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

const tag = writePtr(scratch, runtime.buildImport("new_int"), 2);
const empty = writePtr(scratch + 4, runtime.buildImport("list_nil"));
const record = writePtr(scratch + 8, runtime.buildImport("record_new"), tag, empty);
const got = runtime.buildImport("union_tag_as_int")(record);

if (got !== 2) {
  console.error(`[union-record-tag] expected tag 2, got ${got}`);
  process.exit(1);
}

const payload = writePtr(scratch + 12, runtime.buildImport("tuple_proj"), record, 1);
if (payload !== empty) {
  console.error(`[union-record-tag] expected payload ${empty}, got ${payload}`);
  process.exit(1);
}

const other = writePtr(scratch + 16, runtime.buildImport("new_int"), 99);
// Domain record {id: 2, count: 99} must not steal Effect.Cmd tag 2.
const domain = writePtr(scratch + 20, runtime.buildImport("record_new"), tag, other);
const domainTag = runtime.buildImport("union_tag_as_int")(domain);
if (domainTag !== -1) {
  console.error(`[union-record-tag] domain record must not be a union tag, got ${domainTag}`);
  process.exit(1);
}

console.log("[union-record-tag] ok");
