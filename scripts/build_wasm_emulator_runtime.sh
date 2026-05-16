#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRIDGE_DIR="${ELM_PEBBLE_WASM_BRIDGE_DIR:-${REPO_ROOT}/ide/priv/wasm_emulator/runtime_bridge}"
OUTPUT_DIR="${ELM_PEBBLE_WASM_OUTPUT_DIR:-${REPO_ROOT}/ide/priv/wasm_emulator}"
DEFAULT_CACHE_DIR="${REPO_ROOT}/ide/priv/wasm_emulator/vendor"
CACHE_DIR="${ELM_PEBBLE_WASM_CACHE_DIR:-${DEFAULT_CACHE_DIR}}"

if [ -z "${ELM_PEBBLE_WASM_CACHE_DIR:-}" ] &&
  [ -d "${CACHE_DIR}/pebble-qemu-wasm/.git" ] &&
  [ ! -w "${CACHE_DIR}/pebble-qemu-wasm/.git" ]; then
  CACHE_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/elm-pebble/wasm_emulator"
  echo "Repo WASM vendor checkout is not writable; using cache ${CACHE_DIR}"
fi

QEMU_VERSION="${QEMU_VERSION:-10.1.0}"
QEMU_SRC_OVERRIDE="${QEMU_SRC:-}"
QEMU_SRC="${QEMU_SRC_OVERRIDE:-${CACHE_DIR}/qemu-${QEMU_VERSION}}"
PEBBLE_QEMU_WASM_VENDOR_DIR="${PEBBLE_QEMU_WASM_VENDOR_DIR:-${CACHE_DIR}/pebble-qemu-wasm}"
DOCKER_IMAGE="${PEBBLE_QEMU_WASM_DOCKER_IMAGE:-qemu101-wasm-base}"
FIRMWARE_SOURCE="${PEBBLE_WASM_FIRMWARE_SOURCE:-}"
FIRMWARE_PLATFORM="${PEBBLE_WASM_FIRMWARE_PLATFORM:-emery}"
RUNTIME_QEMU_SRC=""

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 2
  fi
}

patch_qemu_dockerfile() {
  dockerfile="$1"

  # QEMU 10.1's Emscripten image fetches zlib from zlib.net, which can return
  # non-archive content depending on mirrors/proxy behavior. Use zlib's GitHub
  # tag archive instead and fail fast on HTTP errors.
  sed -i \
    -e 's#curl -Ls https://zlib.net[^ ]*/zlib-\$ZLIB_VERSION.tar.xz#curl -fLs https://github.com/madler/zlib/archive/refs/tags/v\$ZLIB_VERSION.tar.gz#g' \
    -e 's#tar xJC /zlib --strip-components=1#tar xzC /zlib --strip-components=1#g' \
    "${dockerfile}"
}

need docker
need git
need tar

mkdir -p "${CACHE_DIR}"
archive="${CACHE_DIR}/qemu-${QEMU_VERSION}.tar.xz"

if [ ! -f "${archive}" ]; then
  need curl
  url="https://download.qemu.org/qemu-${QEMU_VERSION}.tar.xz"

  echo "Downloading ${url}"
  curl -fL "${url}" -o "${archive}"
fi

if [ -n "${QEMU_SRC_OVERRIDE}" ]; then
  if [ ! -d "${QEMU_SRC}" ]; then
    echo "QEMU_SRC does not exist: ${QEMU_SRC}" >&2
    exit 2
  fi
elif [ ! -d "${QEMU_SRC}" ]; then

  echo "Extracting ${archive}"
  tar -C "${CACHE_DIR}" -xf "${archive}"
fi

if [ -z "${QEMU_SRC_OVERRIDE}" ]; then
  RUNTIME_QEMU_SRC="$(mktemp -d)"
  trap 'rm -rf "${RUNTIME_QEMU_SRC}"' EXIT

  echo "Extracting clean runtime QEMU source from ${archive}"
  tar -C "${RUNTIME_QEMU_SRC}" -xf "${archive}"
  QEMU_SRC="${RUNTIME_QEMU_SRC}/qemu-${QEMU_VERSION}"
fi

if ! docker image inspect "${DOCKER_IMAGE}" >/dev/null 2>&1; then
  dockerfile="${QEMU_SRC}/tests/docker/dockerfiles/emsdk-wasm32-cross.docker"
  if [ ! -f "${dockerfile}" ]; then
    echo "Could not find QEMU Emscripten dockerfile: ${dockerfile}" >&2
    exit 2
  fi

  patch_qemu_dockerfile "${dockerfile}"

  echo "Building Docker image ${DOCKER_IMAGE}"
  docker build --progress=plain -t "${DOCKER_IMAGE}" -f "${dockerfile}" "${QEMU_SRC}"
fi

mkdir -p "${OUTPUT_DIR}"

QEMU_SRC="${QEMU_SRC}" \
PEBBLE_QEMU_WASM_VENDOR_DIR="${PEBBLE_QEMU_WASM_VENDOR_DIR}" \
PEBBLE_QEMU_WASM_OUTPUT_DIR="${OUTPUT_DIR}" \
bash "${BRIDGE_DIR}/build_patched_runtime.sh"

copy_firmware_from() {
  src="$1"
  platform="$2"
  [ -f "${src}/qemu_micro_flash.bin" ] || return 1

  if ! raw_micro_flash "${src}/qemu_micro_flash.bin"; then
    echo "Skipping ${src}: qemu_micro_flash.bin is ELF, not raw flash" >&2
    return 1
  fi

  spi="${src}/qemu_spi_flash.bin"
  compressed_spi="${src}/qemu_spi_flash.bin.bz2"

  dest="${OUTPUT_DIR}/firmware/sdk/${platform}"
  mkdir -p "${dest}"
  cp "${src}/qemu_micro_flash.bin" "${dest}/qemu_micro_flash.bin"

  if [ -f "${spi}" ]; then
    cp "${spi}" "${dest}/qemu_spi_flash.bin"
  elif [ -f "${compressed_spi}" ]; then
    need bunzip2
    bunzip2 -ck "${compressed_spi}" > "${dest}/qemu_spi_flash.bin"
  else
    return 1
  fi

  write_firmware_manifest "${platform}" "${dest}"

  if [ ! -f "${OUTPUT_DIR}/firmware/sdk/manifest.json" ]; then
    cp "${dest}/qemu_micro_flash.bin" "${OUTPUT_DIR}/firmware/sdk/qemu_micro_flash.bin"
    cp "${dest}/qemu_spi_flash.bin" "${OUTPUT_DIR}/firmware/sdk/qemu_spi_flash.bin"
    cp "${dest}/manifest.json" "${OUTPUT_DIR}/firmware/sdk/manifest.json"
  fi
}

raw_micro_flash() {
  magic="$(od -An -tx1 -N4 "$1" 2>/dev/null | tr -d ' \n')"
  [ "${magic}" != "7f454c46" ]
}

machine_for_platform() {
  case "$1" in
    aplite) printf '%s\n' "pebble-bb2" ;;
    emery) printf '%s\n' "pebble-snowy-emery-bb" ;;
    basalt) printf '%s\n' "pebble-snowy-bb" ;;
    chalk) printf '%s\n' "pebble-s4-bb" ;;
    diorite | flint) printf '%s\n' "pebble-silk-bb" ;;
    gabbro) printf '%s\n' "pebble-snowy-emery-bb" ;;
    *) printf '%s\n' "pebble-snowy-bb" ;;
  esac
}

cpu_for_platform() {
  case "$1" in
    aplite) printf '%s\n' "cortex-m3" ;;
    *) printf '%s\n' "cortex-m4" ;;
  esac
}

storage_for_platform() {
  case "$1" in
    aplite | diorite | flint) printf '%s\n' "mtdblock" ;;
    *) printf '%s\n' "pflash" ;;
  esac
}

write_firmware_manifest() {
  platform="$1"
  dest="$2"
  machine="$(machine_for_platform "${platform}")"
  cpu="$(cpu_for_platform "${platform}")"
  storage="$(storage_for_platform "${platform}")"
  spi_size="$(wc -c < "${dest}/qemu_spi_flash.bin" | tr -d ' ')"

  cat > "${dest}/manifest.json" <<EOF
{"platform":"${platform}","machine":"${machine}","cpu":"${cpu}","storage":"${storage}","spi_flash_size":${spi_size}}
EOF
}

copy_first_available_firmware() {
  platform="$1"
  copied=0
  roots=(
    "/host-pebble-sdk/SDKs/current/sdk-core/pebble"
    "/var/lib/ide/.pebble-sdk/SDKs/current/sdk-core/pebble"
    "${HOME}/.pebble-sdk/SDKs/current/sdk-core/pebble"
  )
  platforms=("${platform}" emery basalt chalk diorite aplite flint gabbro)

  for root in "${roots[@]}"; do
    [ -d "${root}" ] || continue

    for candidate_platform in "${platforms[@]}"; do
      candidate="${root}/${candidate_platform}/qemu"
      if copy_firmware_from "${candidate}" "${candidate_platform}"; then
        echo "Copied WASM emulator firmware from ${candidate}"
        copied=1
      fi
    done

    for candidate in "${root}"/*/qemu; do
      [ -d "${candidate}" ] || continue
      candidate_platform="$(basename "$(dirname "${candidate}")")"
      if copy_firmware_from "${candidate}" "${candidate_platform}"; then
        echo "Copied WASM emulator firmware from ${candidate}"
        copied=1
      fi
    done
  done

  [ "${copied}" = "1" ]
}

if [ -n "${FIRMWARE_SOURCE}" ]; then
  copy_firmware_from "${FIRMWARE_SOURCE}" "${FIRMWARE_PLATFORM}" || {
    echo "Firmware source is missing expected files: ${FIRMWARE_SOURCE}" >&2
    exit 2
  }
elif ! copy_first_available_firmware "${FIRMWARE_PLATFORM}"; then
  echo "WASM emulator firmware was not found; runtime assets were built successfully." >&2
fi

cat <<EOF
WASM emulator runtime setup complete.

Runtime output:
  ${OUTPUT_DIR}

If firmware is still missing, copy:
  qemu_micro_flash.bin
  qemu_spi_flash.bin

to:
  ${OUTPUT_DIR}/firmware/sdk/<platform>
EOF
