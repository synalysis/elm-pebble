/**
 * Incoming ports that arrive before a subscriber is installed must queue
 * (not return RC 100). Delivery happens when subscriptions register.
 */
import { createRcRuntime, RC_SUCCESS } from "../../../elmc-wasm-runtime/host/rc_runtime.js";

const memory = new WebAssembly.Memory({ initial: 1 });
const runtime = createRcRuntime({});
runtime.setMemory(memory);

const sent = runtime.sendIncomingPort("listen", 0);
if (sent.rc !== RC_SUCCESS || sent.queued !== true) {
  console.error(`[pending-port] expected queued success, got ${JSON.stringify(sent)}`);
  process.exit(1);
}

if (runtime.pendingIncomingPortCount() !== 1) {
  console.error(
    `[pending-port] expected 1 queued payload, got ${runtime.pendingIncomingPortCount()}`
  );
  process.exit(1);
}

console.log("[pending-port] ok");
