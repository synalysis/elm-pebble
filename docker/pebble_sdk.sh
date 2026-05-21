#!/bin/sh
# Pebble SDK helpers for docker/entrypoint.sh (POSIX sh).

pebble_sdk_active?() {
  pebble sdk list 2>/dev/null | grep -q '(active)'
}

seed_bundled_pebble_sdk() {
  target="${DATA_ROOT}/.pebble-sdk"

  if [ -d /opt/pebble-sdk-seed ] && [ ! -d "${target}/SDKs" ]; then
    echo "[entrypoint] Seeding Pebble SDK from image bundle into ${target}..."
    mkdir -p "${DATA_ROOT}"
    cp -a /opt/pebble-sdk-seed "${target}"
  fi
}

install_pebble_sdk_blocking() {
  if [ "${PEBBLE_SDK_VERSION}" = "latest" ]; then
    pebble sdk install latest
    sdk_list="$(pebble sdk list 2>/dev/null || true)"
    latest_installed="$(
      printf "%s\n" "${sdk_list}" | awk '
        /^Installed SDKs:/ {in_installed=1; next}
        /^Available SDKs:/ {in_installed=0}
        in_installed && $1 ~ /^[0-9]+\.[0-9]+(\.[0-9]+)?$/ {print $1}
      ' | sort -V | tail -n 1
    )"

    if [ -n "${latest_installed}" ]; then
      pebble sdk activate "${latest_installed}"
    fi
  else
    if ! pebble sdk activate "${PEBBLE_SDK_VERSION}" >/dev/null 2>&1; then
      pebble sdk install "${PEBBLE_SDK_VERSION}"
      pebble sdk activate "${PEBBLE_SDK_VERSION}"
    fi
  fi
}

install_pebble_sdk_background() {
  (
    echo "[entrypoint] Pebble SDK background install started (version=${PEBBLE_SDK_VERSION})..."
    if install_pebble_sdk_blocking; then
      echo "[entrypoint] Pebble SDK background install finished."
    else
      echo "[entrypoint] Pebble SDK background install failed." >&2
    fi
  ) &
}

ensure_pebble_sdk() {
  if [ "${INSTALL_PEBBLE_SDK}" != "1" ]; then
    return 0
  fi

  seed_bundled_pebble_sdk

  if pebble_sdk_active?; then
    return 0
  fi

  if [ "${PEBBLE_SDK_BLOCKING_INSTALL:-0}" = "1" ]; then
    echo "[entrypoint] Installing Pebble SDK before server start (PEBBLE_SDK_BLOCKING_INSTALL=1)..."
    install_pebble_sdk_blocking
    return 0
  fi

  install_pebble_sdk_background
}
