#!/bin/sh
# WASM emulator runtime helpers for docker/entrypoint.sh (POSIX sh).

WASM_RUNTIME_ASSETS="qemu-system-arm.js qemu-system-arm.wasm qemu-system-arm.worker.js"

wasm_runtime_root() {
  printf '%s\n' "${ELM_PEBBLE_WASM_EMULATOR_ROOT:-${DATA_ROOT}/wasm_emulator}"
}

copy_runtime_asset() {
  src="$1"
  dest="$2"
  if [ -f "${src}" ]; then
    mkdir -p "$(dirname "${dest}")"
    cp -a "${src}" "${dest}"
  fi
}

wasm_runtime_ready() {
  root="$(wasm_runtime_root)"
  for asset in ${WASM_RUNTIME_ASSETS}; do
    [ -f "${root}/${asset}" ] || return 1
  done
}

seed_bundled_wasm_runtime() {
  root="$(wasm_runtime_root)"
  mkdir -p "${root}"

  if wasm_runtime_ready; then
    return 0
  fi

  if [ -f /opt/wasm-emulator-seed/qemu-system-arm.js ]; then
    echo "[entrypoint] Seeding WASM emulator runtime from image bundle into ${root}..."
    for asset in ${WASM_RUNTIME_ASSETS}; do
      copy_runtime_asset "/opt/wasm-emulator-seed/${asset}" "${root}/${asset}"
    done
  fi
}

ensure_wasm_emulator_runtime() {
  seed_bundled_wasm_runtime
}
