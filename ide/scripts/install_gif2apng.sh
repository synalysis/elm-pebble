#!/usr/bin/env bash
# Builds gif2apng into ide/priv/bin (used by mix ide.install_gif2apng).
set -euo pipefail

IDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${IDE_ROOT}/priv/bin"
BIN="${DEST}/gif2apng"
GIF2APNG_VERSION="${GIF2APNG_VERSION:-1.9}"
GIF2APNG_SRC_URL="${GIF2APNG_SRC_URL:-https://sourceforge.net/projects/gif2apng/files/${GIF2APNG_VERSION}/gif2apng-${GIF2APNG_VERSION}-src.zip/download}"

if [[ -x "${BIN}" ]]; then
  echo "gif2apng already installed at ${BIN} ($("${BIN}" 2>&1 | head -1 || true))"
  exit 0
fi

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required tool: $1 (install build-essential, curl, unzip, zlib1g-dev)" >&2
    exit 1
  fi
}

need curl
need unzip
need make
need g++

mkdir -p "${DEST}"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

curl -fsSL -o "${work}/gif2apng.zip" "${GIF2APNG_SRC_URL}"
unzip -q "${work}/gif2apng.zip" -d "${work}/src"
make -C "${work}/src"
install -m 0755 "${work}/src/gif2apng" "${BIN}"

echo "Installed gif2apng to ${BIN}"
