# Pebble QEMU WASM Install Bridge

The IDE page can install PBWs into the browser emulator when the local
`qemu-system-arm.js` exposes one of these runtime APIs:

```js
Module.pebbleInstallPbw(plan)
```

or the lower-level control UART bridge:

```js
Module.pebbleControlSend(bytes)
Module.pebbleControlRecv()
```

or the C exports supplied by the patch in this directory:

```js
Module._pebble_control_wasm_send(ptr, len)
Module._pebble_control_wasm_recv(ptr, capacity)
```

`pebbleControlSend` receives a complete QEMU control packet:

```text
FE ED | protocol=0001 | length | PebbleProtocolFrame | BE EF
```

`pebbleControlRecv` returns either `null`, one packet, or an array of packets in
the same format. The IDE page implements the install protocol itself: BlobDB app
metadata, AppRunState/AppFetch, and PutBytes for binary/resources/worker.

The upstream WASM runtime must connect these functions to `PebbleControl`'s
host-side receive/send buffers. Firmware files are intentionally not stored here.

## Build Locally

This project does not rely on upstream accepting changes. Build a local patched
runtime instead:

```sh
docker compose run --rm wasm-emulator-builder
```

For non-Docker local builds:

```sh
scripts/build_wasm_emulator_runtime.sh
```

The script downloads QEMU 10.1 source if needed, builds the QEMU Emscripten
Docker image, clones `ericmigi/pebble-qemu-wasm`, applies `patches/*.patch`,
runs the upstream WASM build, and copies `qemu-system-arm.js`,
`qemu-system-arm.wasm`, and `qemu-system-arm.worker.js` to the configured WASM
emulator asset root.

You still need local Pebble firmware files:

```text
ide/priv/wasm_emulator/firmware/sdk/qemu_micro_flash.bin
ide/priv/wasm_emulator/firmware/sdk/qemu_spi_flash.bin
```
