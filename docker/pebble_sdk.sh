#!/bin/sh
# Pebble SDK helpers for docker/entrypoint.sh (POSIX sh).

pebble_sdk_list() {
  pebble sdk list 2>/dev/null || true
}

pebble_sdk_active() {
  pebble_sdk_list | grep -q '(active)'
}

pebble_sdk_active_version() {
  pebble_sdk_list | awk '/\(active\)/ {print $1; exit}'
}

# Pebble lists the newest SDK last under "Available SDKs:" (for example 4.17
# after 4.9.x). Do not use sort -V here: 4.17 would sort before 4.9.169.
pebble_sdk_available_latest() {
  pebble_sdk_list | awk '
    /^Available SDKs:/ {in_available=1; next}
    /^Installed SDKs:/ {in_available=0}
    in_available && $1 ~ /^[0-9]/ {last=$1}
    END {print last}
  '
}

pebble_sdk_satisfied() {
  desired="${PEBBLE_SDK_VERSION}"
  active="$(pebble_sdk_active_version)"

  if [ -z "${active}" ]; then
    return 1
  fi

  if [ "${desired}" = "latest" ]; then
    latest="$(pebble_sdk_available_latest)"
    if [ -z "${latest}" ]; then
      return 0
    fi
    [ "${active}" = "${latest}" ]
  else
    [ "${active}" = "${desired}" ]
  fi
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
    latest="$(pebble_sdk_available_latest)"

    if [ -n "${latest}" ]; then
      pebble sdk activate "${latest}"
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
      active="$(pebble_sdk_active_version)"
      echo "[entrypoint] Pebble SDK background install finished (active=${active:-unknown})."
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

  if pebble_sdk_satisfied; then
    return 0
  fi

  active="$(pebble_sdk_active_version)"
  if [ -n "${active}" ]; then
    echo "[entrypoint] Pebble SDK update required (active=${active}, target=${PEBBLE_SDK_VERSION})..."
  fi

  if [ "${PEBBLE_SDK_BLOCKING_INSTALL:-0}" = "1" ]; then
    echo "[entrypoint] Installing Pebble SDK before server start (PEBBLE_SDK_BLOCKING_INSTALL=1)..."
    install_pebble_sdk_blocking
    return 0
  fi

  install_pebble_sdk_background
}
