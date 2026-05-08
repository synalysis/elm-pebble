#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IDE_DIR="${SCRIPT_DIR}/ide"
ASSETS_DIR="${IDE_DIR}/assets"

if [ ! -d "${IDE_DIR}" ]; then
  echo "Could not find ide/ directory at: ${IDE_DIR}" >&2
  exit 1
fi

cd "${IDE_DIR}"

echo "Ensuring elmc dependency is compiled..."
mix deps.get
mix deps.compile elm_ex elmc

echo "Ensuring IDE asset dependencies are installed..."
if ! command -v npm >/dev/null 2>&1; then
  echo "npm is required to install IDE asset dependencies, but it was not found in PATH." >&2
  exit 1
fi

if [ ! -d "${ASSETS_DIR}/node_modules" ] || [ "${ASSETS_DIR}/package-lock.json" -nt "${ASSETS_DIR}/node_modules/.package-lock.json" ]; then
  npm ci --prefix "${ASSETS_DIR}"
else
  echo "IDE asset dependencies are already installed."
fi

echo "Running DB migrations..."
mix ecto.migrate

echo "Starting IDE server at http://localhost:4000 ..."
exec mix phx.server
