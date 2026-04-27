#!/bin/sh
set -eu

DATA_ROOT="${IDE_DATA_ROOT:-/var/lib/ide}"
PROJECTS_ROOT="${PROJECTS_ROOT:-$DATA_ROOT/workspace_projects}"
SETTINGS_FILE="${SETTINGS_FILE:-$DATA_ROOT/config/settings.json}"
PEBBLE_SDK_VERSION="${PEBBLE_SDK_VERSION:-latest}"
INSTALL_PEBBLE_SDK="${INSTALL_PEBBLE_SDK:-1}"

mkdir -p "$DATA_ROOT" "$PROJECTS_ROOT" "$(dirname "$SETTINGS_FILE")"

if [ ! -f "$SETTINGS_FILE" ]; then
  printf '{\n  "auto_format_on_save": false,\n  "debug_mode": false,\n  "editor_mode": "regular"\n}\n' > "$SETTINGS_FILE"
fi

elm --version >/dev/null
pebble --version >/dev/null

if [ "$INSTALL_PEBBLE_SDK" = "1" ]; then
  sdk_list="$(pebble sdk list 2>/dev/null || true)"

  if [ "$PEBBLE_SDK_VERSION" = "latest" ]; then
    case "$sdk_list" in
      *"(active)"*) ;;
      *)
        pebble sdk install latest
        sdk_list="$(pebble sdk list 2>/dev/null || true)"
        latest_installed="$(
          printf "%s\n" "$sdk_list" | awk '
            /^Installed SDKs:/ {in_installed=1; next}
            /^Available SDKs:/ {in_installed=0}
            in_installed && $1 ~ /^[0-9]+\.[0-9]+(\.[0-9]+)?$/ {print $1}
          ' | sort -V | tail -n 1
        )"

        if [ -n "$latest_installed" ]; then
          pebble sdk activate "$latest_installed"
        fi
        ;;
    esac
  else
    if ! pebble sdk activate "$PEBBLE_SDK_VERSION" >/dev/null 2>&1; then
      pebble sdk install "$PEBBLE_SDK_VERSION"
      pebble sdk activate "$PEBBLE_SDK_VERSION"
    fi
  fi
fi

/opt/ide/bin/ide eval "Ide.Release.migrate"
exec /opt/ide/bin/ide start
