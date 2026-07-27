#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CORPUS_DIR="${ROOT_DIR}/vendor/elm-run-test_corpus"
LOCK_FILE="${ROOT_DIR}/vendor/elm-run-test_corpus.lock"

if [[ ! -d "${CORPUS_DIR}/.git" ]]; then
  echo "Initializing elm-run test_corpus submodule..."
  git -C "${ROOT_DIR}" submodule update --init --depth 1 vendor/elm-run-test_corpus
fi

echo "Updating elm-run test_corpus submodule..."
git -C "${ROOT_DIR}" submodule update --remote --depth 1 vendor/elm-run-test_corpus

SHA="$(git -C "${CORPUS_DIR}" rev-parse HEAD)"
echo "${SHA}" > "${LOCK_FILE}"

echo "Pinned corpus SHA: ${SHA}"
echo "Regenerating corpus index..."
(
  cd "${ROOT_DIR}/elmc"
  MIX_ENV=test mix run -e 'Elmc.Test.ElmRunCorpus.write_index!()'
)

echo "Done."
