#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IDE_DIR="${SCRIPT_DIR}/ide"

if [ ! -d "${IDE_DIR}" ]; then
  echo "Could not find ide/ directory at: ${IDE_DIR}" >&2
  exit 1
fi

cd "${IDE_DIR}"

echo "Ensuring elmc dependency is compiled..."
mix deps.get
mix deps.compile elm_ex elmc

echo "Running DB migrations..."
mix ecto.migrate

echo "Starting IDE server at http://localhost:4000 ..."
exec mix phx.server
