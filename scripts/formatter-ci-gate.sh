#!/usr/bin/env bash
# Formatter unit tests + elm-format parity gate for CI and local verification.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASELINE="${ROOT}/ide/priv/formatter_parity_baseline.json"
FIXTURES_CACHE="${FORMATTER_FIXTURES_CACHE:-/tmp/elm-format-good-fixtures}"

export TEST_ULIMIT_V_KB="${TEST_ULIMIT_V_KB:-6291456}"
export ELIXIR_ERL_OPTIONS="${ELIXIR_ERL_OPTIONS:-+S 1:1 +MMscs 256}"

ensure_elm_format() {
  if command -v elm-format >/dev/null 2>&1; then
    return 0
  fi

  if ! command -v npm >/dev/null 2>&1; then
    echo "formatter-ci-gate: npm is required to install elm-format" >&2
    exit 1
  fi

  npm install -g elm-format@0.8.8
}

ensure_fixtures() {
  if [ -n "${ELM_FORMAT_FIXTURES_ROOT:-}" ] && [ -d "${ELM_FORMAT_FIXTURES_ROOT}" ]; then
    return 0
  fi

  local vendor="${ROOT}/vendor/elm-format/tests/test-files/good"
  if [ -d "${vendor}" ]; then
    export ELM_FORMAT_FIXTURES_ROOT="${vendor}"
    return 0
  fi

  if [ ! -d "${FIXTURES_CACHE}" ]; then
    clone_dir="$(mktemp -d)"
    git clone --depth 1 --filter=blob:none --sparse https://github.com/avh4/elm-format.git "${clone_dir}"
    (
      cd "${clone_dir}"
      git sparse-checkout set tests/test-files/good
    )
    mkdir -p "$(dirname "${FIXTURES_CACHE}")"
    mv "${clone_dir}/tests/test-files/good" "${FIXTURES_CACHE}"
    rm -rf "${clone_dir}"
  fi

  export ELM_FORMAT_FIXTURES_ROOT="${FIXTURES_CACHE}"
}

ensure_elm_format
ensure_fixtures

if [ ! -f "${BASELINE}" ]; then
  echo "formatter-ci-gate: missing baseline ${BASELINE}" >&2
  exit 1
fi

echo "formatter-ci-gate: fixtures=${ELM_FORMAT_FIXTURES_ROOT}"
echo "formatter-ci-gate: running elm_ex pretty frontend tests"

"${ROOT}/scripts/mix-test-limited.sh" elm_ex \
  test/frontend/pretty_test.exs \
  test/frontend/source_regions_test.exs \
  test/frontend/preserve_normalize_test.exs \
  test/frontend/body_layout_test.exs \
  test/frontend/source_comments_test.exs \
  test/frontend/generated_contract_builder_test.exs

echo "formatter-ci-gate: running ide formatter tests"

"${ROOT}/scripts/mix-test-limited.sh" ide \
  test/ide/formatter_test.exs \
  test/ide/formatter/parity_test.exs \
  test/ide/formatter/edit_engine_test.exs \
  test/mix/tasks/formatter_parity_task_test.exs \
  test/mix/tasks/formatter_certify_task_test.exs

echo "formatter-ci-gate: compiling ide"
(
  cd "${ROOT}/ide"
  mix deps.get
  mix compile --warnings-as-errors
)

echo "formatter-ci-gate: running elm-format parity phase C"
(
  cd "${ROOT}/ide"
  mix formatter.parity \
    --engine pretty \
    --phase C \
    --fixtures "${ELM_FORMAT_FIXTURES_ROOT}" \
    --baseline "${BASELINE}"
)

echo "formatter-ci-gate: ok"
