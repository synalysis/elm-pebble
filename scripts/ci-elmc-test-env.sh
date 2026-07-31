#!/usr/bin/env bash
# Shared CI/local env for elmc test compile + host-binary caches.
# Source from workflows:  # shellcheck source=./scripts/ci-elmc-test-env.sh
#   . ./scripts/ci-elmc-test-env.sh
#
# Uses a stable disk-backed cache root (not /tmp) so GitHub Actions cache
# restore and warm local runs share the same trees.
set -a
TEST_ULIMIT_V_KB="${TEST_ULIMIT_V_KB:-6291456}"
ELIXIR_ERL_OPTIONS="${ELIXIR_ERL_OPTIONS:-+S 1:1 +MMscs 256}"

XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"
ELMC_TEST_COMPILE_CACHE_DIR="${ELMC_TEST_COMPILE_CACHE_DIR:-${XDG_CACHE_HOME}/elm-pebble/elmc-test-compile-cache}"
ELMC_TEST_IR_CACHE_DIR="${ELMC_TEST_IR_CACHE_DIR:-${ELMC_TEST_COMPILE_CACHE_DIR}/ir}"
set +a

mkdir -p "${ELMC_TEST_COMPILE_CACHE_DIR}" "${ELMC_TEST_IR_CACHE_DIR}"
