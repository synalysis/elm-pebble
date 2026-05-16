#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WASM_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

UPSTREAM_URL="${PEBBLE_QEMU_WASM_URL:-https://github.com/ericmigi/pebble-qemu-wasm.git}"
UPSTREAM_REF="${PEBBLE_QEMU_WASM_REF:-main}"
VENDOR_DIR="${PEBBLE_QEMU_WASM_VENDOR_DIR:-${WASM_ROOT}/vendor/pebble-qemu-wasm}"
OUTPUT_DIR="${ELM_PEBBLE_WASM_OUTPUT_DIR:-${PEBBLE_QEMU_WASM_OUTPUT_DIR:-${WASM_ROOT}}}"

if [ -z "${QEMU_SRC:-}" ]; then
  echo "QEMU_SRC must point to a QEMU 10.1 source checkout." >&2
  echo "Example: QEMU_SRC=\$HOME/dev/qemu-10.1.0 $0" >&2
  exit 2
fi

if [ ! -d "${QEMU_SRC}" ]; then
  echo "QEMU_SRC does not exist: ${QEMU_SRC}" >&2
  exit 2
fi

mkdir -p "$(dirname "${VENDOR_DIR}")" "${OUTPUT_DIR}"

if [ ! -d "${VENDOR_DIR}/.git" ]; then
  git clone "${UPSTREAM_URL}" "${VENDOR_DIR}"
fi

git_vendor() {
  git -c "safe.directory=${VENDOR_DIR}" -C "${VENDOR_DIR}" "$@"
}

git_vendor fetch --tags origin "${UPSTREAM_REF}"
git_vendor checkout "${UPSTREAM_REF}"
git_vendor reset --hard "origin/${UPSTREAM_REF}" >/dev/null
git_vendor clean -fd >/dev/null

for patch in "${SCRIPT_DIR}/patches/"*.patch; do
  [ -f "${patch}" ] || continue
  if git_vendor apply --check "${patch}" >/dev/null 2>&1; then
    git_vendor apply "${patch}"
  elif git_vendor apply --reverse --check "${patch}" >/dev/null 2>&1; then
    echo "Patch already applied: ${patch}" >&2
  else
    echo "Patch is incompatible and was not applied: ${patch}" >&2
    exit 2
  fi
done

python3 - "${VENDOR_DIR}/build_wasm.sh" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
source = path.read_text()
verification = (
    'if ! grep -q "WCYCLE_WRITE_BUFFER_DATA" hw/block/pflash_cfi02.c; then\n'
    '    echo "S29VS pflash patch was not applied" >&2\n'
    '    exit 2\n'
    'fi\n'
)
if 'S29VS pflash patch was not applied' not in source:
    source = source.replace(
        '# Patch Kconfig\n',
        '# Verify critical storage flash patch\n' + verification + '\n# Patch Kconfig\n',
    )
if "_pebble_control_wasm_send" in source and "_pebble_control_wasm_recv" in source:
    path.write_text(source)
    raise SystemExit(0)
exports = (
    "-flto "
    "-sEXPORTED_FUNCTIONS=['_main','_malloc','_free',"
    "'_pebble_control_wasm_send','_pebble_control_wasm_recv'] "
    "-sEXPORTED_RUNTIME_METHODS=['ccall','cwrap']"
)
updated = source.replace('--extra-ldflags="-flto"', f'--extra-ldflags="{exports}"')
if updated == source:
    raise SystemExit("Could not patch build_wasm.sh exported functions")
path.write_text(updated)
PY

QEMU_SRC="${QEMU_SRC}" bash "${VENDOR_DIR}/build_wasm.sh"

cp "${VENDOR_DIR}/web/qemu-system-arm.js" "${OUTPUT_DIR}/qemu-system-arm.js"
cp "${VENDOR_DIR}/web/qemu-system-arm.wasm" "${OUTPUT_DIR}/qemu-system-arm.wasm"
cp "${VENDOR_DIR}/web/qemu-system-arm.worker.js" "${OUTPUT_DIR}/qemu-system-arm.worker.js"

if ! grep -q "_pebble_control_wasm_send" "${OUTPUT_DIR}/qemu-system-arm.js" ||
  ! grep -q "_pebble_control_wasm_recv" "${OUTPUT_DIR}/qemu-system-arm.js"; then
  echo "Built qemu-system-arm.js does not expose the Pebble control WASM bridge." >&2
  exit 2
fi

cat <<EOF
Patched Pebble QEMU WASM runtime copied to:
  ${OUTPUT_DIR}

The wrapper build script copies SDK firmware when a Pebble SDK is available.
If firmware is still missing, place SDK firmware here:
  ${OUTPUT_DIR}/firmware/sdk/qemu_micro_flash.bin
  ${OUTPUT_DIR}/firmware/sdk/qemu_spi_flash.bin

The IDE will report the install bridge as ready when qemu-system-arm.js exposes:
  _pebble_control_wasm_send
  _pebble_control_wasm_recv
EOF
