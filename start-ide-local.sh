#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IDE_DIR="${SCRIPT_DIR}/ide"
ASSETS_DIR="${IDE_DIR}/assets"

# Load KEY=VALUE pairs from a dotenv file. Existing environment variables win.
load_dotenv() {
  local env_file="$1"
  local line key value

  if [ ! -f "${env_file}" ]; then
    return 0
  fi

  echo "Loading environment from ${env_file} ..."

  while IFS= read -r line || [ -n "${line}" ]; do
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    [ -z "${line}" ] && continue
    [ "${line:0:1}" = "#" ] && continue

    if [ "${line:0:7}" = "export " ]; then
      line="${line:7}"
      line="${line#"${line%%[![:space:]]*}"}"
    fi

    case "${line}" in
      *=*) ;;
      *)
        echo "Ignoring invalid .env line: ${line}" >&2
        continue
        ;;
    esac

    key="${line%%=*}"
    value="${line#*=}"
    key="${key%"${key##*[![:space:]]}"}"

    case "${key}" in
      [A-Za-z_]*) ;;
      *)
        echo "Ignoring invalid .env key: ${key}" >&2
        continue
        ;;
    esac

    case "${key}" in
      *[!A-Za-z0-9_]*)
        echo "Ignoring invalid .env key: ${key}" >&2
        continue
        ;;
    esac

    if [ "${#value}" -ge 2 ]; then
      case "${value}" in
        \"*\") value="${value:1:${#value}-2}" ;;
        \'*\') value="${value:1:${#value}-2}" ;;
      esac
    fi

    if [ -n "${!key+x}" ]; then
      continue
    fi

    export "${key}=${value}"
  done < "${env_file}"
}

load_dotenv "${SCRIPT_DIR}/.env"

if [ ! -d "${IDE_DIR}" ]; then
  echo "Could not find ide/ directory at: ${IDE_DIR}" >&2
  exit 1
fi

cd "${IDE_DIR}"

echo "Ensuring elmc dependency is compiled..."
mix deps.get
mix deps.compile elm_ex elmc elmx

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
