#!/bin/sh
# WASM emulator runtime helpers for docker/entrypoint.sh (POSIX sh).

wasm_runtime_root() {
  printf '%s\n' "${ELM_PEBBLE_WASM_EMULATOR_ROOT:-${DATA_ROOT}/wasm_emulator}"
}

wasm_runtime_ready() {
  root="$(wasm_runtime_root)"
  [ -f "${root}/qemu-system-arm.js" ] &&
    [ -f "${root}/qemu-system-arm.wasm" ] &&
    [ -f "${root}/qemu-system-arm.worker.js" ]
}

wasm_build_log() {
  printf '%s\n' "$(wasm_runtime_root)/build.log"
}

wasm_build_lock() {
  printf '%s\n' "$(wasm_runtime_root)/.build_in_progress"
}

seed_bundled_wasm_runtime() {
  root="$(wasm_runtime_root)"

  if wasm_runtime_ready; then
    return 0
  fi

  if [ -f /opt/wasm-emulator-seed/qemu-system-arm.js ]; then
    echo "[entrypoint] Seeding WASM emulator runtime from image bundle into ${root}..."
    mkdir -p "${root}"
    cp -a /opt/wasm-emulator-seed/. "${root}/"
  fi
}

build_wasm_runtime_background() {
  if wasm_runtime_ready; then
    return 0
  fi

  if [ "${ELM_PEBBLE_WASM_BUILD_ON_START:-1}" = "0" ]; then
    echo "[entrypoint] WASM emulator runtime build disabled (ELM_PEBBLE_WASM_BUILD_ON_START=0)."
    return 0
  fi

  lock="$(wasm_build_lock)"
  if [ -f "${lock}" ]; then
    echo "[entrypoint] WASM emulator runtime build already in progress."
    return 0
  fi

  build_script="/opt/wasm-emulator-build/build_wasm_emulator_runtime.sh"
  if [ ! -f "${build_script}" ]; then
    echo "[entrypoint] WASM emulator build script not found; browser WASM runtime will remain unavailable."
    return 0
  fi

  root="$(wasm_runtime_root)"
  mkdir -p "${root}" "$(dirname "${lock}")"
  : > "${lock}"

  (
    log="$(wasm_build_log)"
    echo "[entrypoint] WASM emulator runtime background build started..."
    export ELM_PEBBLE_WASM_OUTPUT_DIR="${root}"
    export ELM_PEBBLE_WASM_CACHE_DIR="${ELM_PEBBLE_WASM_CACHE_DIR:-${root}/cache}"
    export ELM_PEBBLE_WASM_BRIDGE_DIR="/opt/wasm-emulator-build/runtime_bridge"
    if sh "${build_script}" >> "${log}" 2>&1; then
      echo "[entrypoint] WASM emulator runtime background build finished."
    else
      echo "[entrypoint] WASM emulator runtime background build failed. See ${log}" >&2
    fi
    rm -f "${lock}"
  ) &
}

ensure_wasm_emulator_runtime() {
  seed_bundled_wasm_runtime
  build_wasm_runtime_background
}
