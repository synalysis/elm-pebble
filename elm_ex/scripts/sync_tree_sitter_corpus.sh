#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CORPUS_DIR="${ROOT_DIR}/vendor/tree-sitter-elm-test-corpus"
LOCK_FILE="${ROOT_DIR}/vendor/tree-sitter-elm-test-corpus.lock"

if [[ ! -d "${CORPUS_DIR}/.git" ]]; then
  echo "Initializing tree-sitter-elm test corpus submodule..."
  git -C "${ROOT_DIR}" submodule update --init --depth 1 vendor/tree-sitter-elm-test-corpus
fi

echo "Updating tree-sitter-elm test corpus submodule..."
git -C "${ROOT_DIR}" submodule update --remote --depth 1 vendor/tree-sitter-elm-test-corpus

SHA="$(git -C "${CORPUS_DIR}" rev-parse HEAD)"
echo "${SHA}" > "${LOCK_FILE}"

echo "Pinned corpus SHA: ${SHA}"
echo "Done. Refresh elm_ex/docs/tree_sitter_corpus_baseline.json after intentional corpus updates."
