#!/bin/sh
set -eu

DATA_ROOT="${IDE_DATA_ROOT:-/var/lib/ide}"
PROJECTS_ROOT="${PROJECTS_ROOT:-$DATA_ROOT/workspace_projects}"
SETTINGS_FILE="${SETTINGS_FILE:-$DATA_ROOT/config/settings.json}"
AUTH_MODE="${IDE_AUTH_MODE:-local}"
PEBBLE_SDK_VERSION="${PEBBLE_SDK_VERSION:-4.9.169}"
INSTALL_PEBBLE_SDK="${INSTALL_PEBBLE_SDK:-1}"

. /docker/pebble_sdk.sh

mkdir -p "$DATA_ROOT" "$PROJECTS_ROOT"

case "$AUTH_MODE" in
  public|public_pebble|public_custom)
    ;;
  *)
    mkdir -p "$(dirname "$SETTINGS_FILE")"

    if [ ! -f "$SETTINGS_FILE" ]; then
      printf '{\n  "auto_format_on_save": false,\n  "debug_mode": false,\n  "editor_mode": "regular"\n}\n' > "$SETTINGS_FILE"
    fi
    ;;
esac

elm --version >/dev/null
pebble --version >/dev/null

ensure_pebble_sdk

export ELM_PEBBLE_QEMU_BIN="${ELM_PEBBLE_QEMU_BIN:-$DATA_ROOT/.pebble-sdk/SDKs/current/toolchain/bin/qemu-pebble}"
export ELM_PEBBLE_PYPKJS_BIN="${ELM_PEBBLE_PYPKJS_BIN:-/opt/pipx/venvs/pebble-tool/bin/pypkjs}"
export ELM_PEBBLE_QEMU_IMAGE_ROOT="${ELM_PEBBLE_QEMU_IMAGE_ROOT:-$DATA_ROOT/.pebble-sdk/SDKs/current/sdk-core/pebble}"
export ELM_PEBBLE_QEMU_DATA_ROOT="${ELM_PEBBLE_QEMU_DATA_ROOT:-/usr/share/qemu}"
export ELM_PEBBLE_QEMU_DOWNLOAD_IMAGES="${ELM_PEBBLE_QEMU_DOWNLOAD_IMAGES:-1}"

/opt/ide/bin/ide eval "Ide.Release.setup()"
exec /opt/ide/bin/ide start
