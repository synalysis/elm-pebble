#!/usr/bin/env bash
# Seed $ELM_HOME/0.19.1/packages (default ~/.elm) with Elm 0.19.1 packages needed
# for cold CI / empty-home compiles. Bridge reads these when fixtures declare deps.
#
# Usage:
#   ./scripts/seed-elm-packages.sh
#   ELM_HOME=/path/to/elm-home ./scripts/seed-elm-packages.sh
#   SEED_FROM_ELM_JSON=elm_pebble_dev/elm.json ./scripts/seed-elm-packages.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ELM_HOME="${ELM_HOME:-${HOME}/.elm}"
PACKAGES_ROOT="${ELM_HOME}/0.19.1/packages"
mkdir -p "${PACKAGES_ROOT}"

# author/name/version — keep in sync with fixture elm.json direct deps used in CI.
PACKAGES=(
  elm/browser/1.0.2
  elm/bytes/1.0.8
  elm/core/1.0.5
  elm/file/1.0.5
  elm/html/1.0.0
  elm/html/1.0.1
  elm/http/2.0.0
  elm/json/1.1.3
  elm/json/1.1.4
  elm/parser/1.1.0
  elm/project-metadata-utils/1.0.2
  elm/random/1.0.0
  elm/regex/1.0.0
  elm/svg/1.0.1
  elm/time/1.0.0
  elm/url/1.0.0
  elm/virtual-dom/1.0.2
  elm/virtual-dom/1.0.3
  elm/virtual-dom/1.0.5
  ianmackenzie/elm-1d-parameter/1.0.1
  ianmackenzie/elm-float-extra/1.1.0
  ianmackenzie/elm-geometry/4.0.0
  ianmackenzie/elm-interval/3.1.0
  ianmackenzie/elm-triangular-mesh/1.1.0
  ianmackenzie/elm-units/2.10.0
  ianmackenzie/elm-units-interval/3.2.0
  jcberentsen/elm-wiring-diagrams/5.4.7
  mbr/elm-wss/2.0.0
  w0rm/elm-physics/6.2.0
)

collect_from_elm_json() {
  local elm_json="$1"
  python3 - "$elm_json" <<'PY'
import json, sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
deps = data.get("dependencies", {})
items = {}
if isinstance(deps, dict) and ("direct" in deps or "indirect" in deps):
    items.update(deps.get("direct") or {})
    items.update(deps.get("indirect") or {})
elif isinstance(deps, dict):
    # Package elm.json uses ranges ("1.0.0 <= v < 2.0.0"); skip those.
    for k, v in deps.items():
        if isinstance(v, str) and " " not in v and "<" not in v and ">" not in v:
            items[k] = v

for pkg, ver in sorted(items.items()):
    if isinstance(ver, str) and " " not in ver and "<" not in ver and ">" not in ver:
        print(f"{pkg}/{ver}")
PY
}

# Packages that are not published with GitHub version tags (Lamdera injects
# lamdera/*; the public repo has no 1.0.0 tag). Prefer vendored copies under
# elm_pebble_dev/vendor/elm-packages/<author>/<name>/<ver>/.
vendor_pkg_path() {
  local author="$1" name="$2" ver="$3"
  echo "${ROOT}/elm_pebble_dev/vendor/elm-packages/${author}/${name}/${ver}"
}

install_from_dir() {
  local src="$1" dest="$2" spec="$3"
  if [ ! -d "${src}/src" ] || [ ! -f "${src}/elm.json" ]; then
    return 1
  fi
  echo "Copying ${spec} from ${src}..."
  mkdir -p "$(dirname "${dest}")"
  rm -rf "${dest}"
  cp -a "${src}" "${dest}"
  return 0
}

download_archive_to_dest() {
  local url="$1" dest="$2" spec="$3"
  local tmp extract_dir
  tmp="$(mktemp -d)"
  if ! curl -fsSL --retry 3 --retry-delay 1 "${url}" -o "${tmp}/pkg.tar.gz"; then
    rm -rf "${tmp}"
    return 1
  fi
  tar -xzf "${tmp}/pkg.tar.gz" -C "${tmp}"
  extract_dir="$(find "${tmp}" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  if [ -z "${extract_dir}" ] || [ ! -f "${extract_dir}/elm.json" ]; then
    rm -rf "${tmp}"
    return 1
  fi
  mkdir -p "$(dirname "${dest}")"
  rm -rf "${dest}"
  mv "${extract_dir}" "${dest}"
  rm -rf "${tmp}"
  echo "Seeded ${spec} from ${url}"
  return 0
}

seed_one() {
  local spec="$1"
  local author name ver dest
  author="${spec%%/*}"
  local rest="${spec#*/}"
  name="${rest%%/*}"
  ver="${rest#*/}"
  dest="${PACKAGES_ROOT}/${author}/${name}/${ver}"

  if [ -d "${dest}/src" ] && [ -f "${dest}/elm.json" ]; then
    return 0
  fi

  # Repo-vendored packages (offline / no GitHub tags).
  local vendor_pkg
  vendor_pkg="$(vendor_pkg_path "${author}" "${name}" "${ver}")"
  if install_from_dir "${vendor_pkg}" "${dest}" "${spec}"; then
    return 0
  fi

  # Prefer already-downloaded sources under the user's real ~/.elm when CI ELM_HOME
  # is a workspace cache (copy is faster/more reliable than GitHub tags).
  local home_pkg="${HOME}/.elm/0.19.1/packages/${author}/${name}/${ver}"
  if [ "${ELM_HOME}" != "${HOME}/.elm" ] && install_from_dir "${home_pkg}" "${dest}" "${spec}"; then
    return 0
  fi

  echo "Seeding ${spec}..."
  # Standard Elm package tags, then v-prefixed tags.
  if download_archive_to_dest \
    "https://github.com/${author}/${name}/archive/refs/tags/${ver}.tar.gz" \
    "${dest}" "${spec}"; then
    return 0
  fi
  if download_archive_to_dest \
    "https://github.com/${author}/${name}/archive/refs/tags/v${ver}.tar.gz" \
    "${dest}" "${spec}"; then
    return 0
  fi

  # Last resort for untagged public repos (lamdera/codecs has no version tags).
  if download_archive_to_dest \
    "https://github.com/${author}/${name}/archive/refs/heads/master.tar.gz" \
    "${dest}" "${spec}"; then
    return 0
  fi
  if download_archive_to_dest \
    "https://github.com/${author}/${name}/archive/refs/heads/main.tar.gz" \
    "${dest}" "${spec}"; then
    return 0
  fi

  echo "error: failed to seed ${spec} (no vendor copy, ~/.elm cache, or GitHub archive)" >&2
  return 1
}

ALL_SPECS=("${PACKAGES[@]}")

if [[ -n "${SEED_FROM_ELM_JSON:-}" ]]; then
  elm_json_path="${SEED_FROM_ELM_JSON}"
  if [[ "${elm_json_path}" != /* ]]; then
    elm_json_path="${ROOT}/${elm_json_path}"
  fi
  if [[ ! -f "${elm_json_path}" ]]; then
    echo "error: SEED_FROM_ELM_JSON not found: ${elm_json_path}" >&2
    exit 1
  fi

  # First pass: seed direct+indirect pins from the app elm.json (may miss nested
  # deps until package elm.json files exist locally).
  mapfile -t FROM_APP < <(collect_from_elm_json "${elm_json_path}" || true)
  ALL_SPECS+=("${FROM_APP[@]}")
fi

# Unique preserve order
declare -A SEEN=()
UNIQUE=()
for spec in "${ALL_SPECS[@]}"; do
  [[ -n "${spec}" ]] || continue
  if [[ -z "${SEEN[$spec]+x}" ]]; then
    SEEN[$spec]=1
    UNIQUE+=("$spec")
  fi
done

failed=0
for spec in "${UNIQUE[@]}"; do
  if ! seed_one "${spec}"; then
    failed=1
  fi
done

if [ "${failed}" -ne 0 ]; then
  echo "error: one or more elm packages failed to seed into ${PACKAGES_ROOT}" >&2
  exit 1
fi

echo "Elm packages ready under ${PACKAGES_ROOT}"
