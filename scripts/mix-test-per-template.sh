#!/usr/bin/env bash
# Run a per-template ExUnit file one template at a time (`ELMC_HOST_SMOKE_TEMPLATE`).
#
# Batching many :slow template compiles in a single mix test process can allocate
# tens of GB even with ulimit. Use this for tests generated from PlanStrictTemplates.
#
# Usage:
#   ./scripts/mix-test-per-template.sh <test_file.exs> [template_name …]
#
# With no template args, runs every name from Elmc.TestSupport.PlanStrictTemplates
# (or `rc_host_smoke_names/0` for `watchface_rc_track_smoke_test.exs`).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ULIMIT_V_KB="${TEST_ULIMIT_V_KB:-6291456}"
export ELIXIR_ERL_OPTIONS="${ELIXIR_ERL_OPTIONS:-+S 1:1 +MMscs 256}"

TEST_FILE="${1:?usage: mix-test-per-template.sh <test_file.exs> [template …]}"
shift

(cd "${ROOT}/elmc" && MIX_ENV=test mix compile --force-off >/dev/null 2>&1) || \
  (cd "${ROOT}/elmc" && MIX_ENV=test mix compile >/dev/null 2>&1)

if [ "$#" -gt 0 ]; then
  templates=("$@")
else
  NAMES_EXPR='Elmc.TestSupport.PlanStrictTemplates.names()'
  case "${TEST_FILE}" in
    *watchface_rc_track_smoke_test.exs)
      NAMES_EXPR='Elmc.TestSupport.PlanStrictTemplates.rc_host_smoke_names()'
      ;;
    *watchface_tea_semantic_smoke_test.exs)
      NAMES_EXPR='Elmc.TestSupport.PlanStrictTemplates.host_smoke_names()'
      ;;
  esac
  mapfile -t templates < <(
    cd "${ROOT}/elmc"
    MIX_ENV=test mix run --no-compile --no-start -e "
      ${NAMES_EXPR}
      |> Enum.each(&IO.puts/1)
    " 2>/dev/null
  )
fi

passed=0
failed=()

for template in "${templates[@]}"; do
  printf '%s: %s … ' "${TEST_FILE}" "${template}"
  if ELMC_HOST_SMOKE_TEMPLATE="${template}" "${ROOT}/scripts/mix-test-limited.sh" elmc "${TEST_FILE}" --include slow --force >/dev/null 2>&1; then
    echo ok
    passed=$((passed + 1))
  else
    echo FAIL
    failed+=("${template}")
    ELMC_HOST_SMOKE_TEMPLATE="${template}" "${ROOT}/scripts/mix-test-limited.sh" elmc "${TEST_FILE}" --include slow --force 2>&1 | tail -8 || true
  fi
done

echo "---"
echo "passed=${passed} failed=${#failed[@]}"
if [ "${#failed[@]}" -gt 0 ]; then
  printf '  %s\n' "${failed[@]}"
  exit 1
fi
