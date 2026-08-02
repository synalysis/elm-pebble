#!/usr/bin/env bash
# Run a per-template ExUnit file in small BEAM batches (`ELMC_HOST_SMOKE_TEMPLATE`).
#
# Batching many :slow template compiles in a single mix test process can allocate
# tens of GB even with ulimit. This script limits batch size and isolates failures.
#
# Usage:
#   ./scripts/mix-test-per-template.sh <test_file.exs> [template_name …]
#
# Optional:
#   ELMC_TEST_TEMPLATE_BATCH=N  — templates per BEAM. Defaults:
#     4 for compile/typecheck gates (strict, reachable, fusion, opcode)
#     1 for host-link smokes (watchface_rc_track / watchface_tea_semantic)
#   Do **not** pass mix test --force here: force-recompiling beams invalidates
#   Elmc.TestSupport.CompileCache via ebin mtimes on every template.
#
# With no template args, runs every name from Elmc.TestSupport.PlanStrictTemplates
# (or `rc_host_smoke_names/0` / `host_smoke_names/0` for host smokes).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./ci-elmc-test-env.sh
. "${ROOT}/scripts/ci-elmc-test-env.sh"
export TEST_ULIMIT_V_KB="${TEST_ULIMIT_V_KB:-6291456}"
export ELIXIR_ERL_OPTIONS="${ELIXIR_ERL_OPTIONS:-+S 1:1 +MMscs 256}"

TEST_FILE="${1:?usage: mix-test-per-template.sh <test_file.exs> [template …]}"
shift

case "${TEST_FILE}" in
  elmx/*|*tea_playbook_smoke_test.exs)
    PKG=elmx
    ;;
  ide/*)
    PKG=ide
    ;;
  *)
    PKG=elmc
    ;;
esac

case "${TEST_FILE}" in
  *watchface_rc_track_smoke_test.exs|*watchface_tea_semantic_smoke_test.exs|*template_tea_scenario_smoke_test.exs|*tea_playbook_smoke_test.exs)
    DEFAULT_BATCH=1
    ;;
  *)
    DEFAULT_BATCH=4
    ;;
esac
BATCH="${ELMC_TEST_TEMPLATE_BATCH:-${DEFAULT_BATCH}}"

# Compile once up front. Never --force in the per-template loop (cache identity).
(cd "${ROOT}/${PKG}" && MIX_ENV=test mix compile) >/dev/null

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
    *template_tea_scenario_smoke_test.exs)
      NAMES_EXPR='Elmc.TestSupport.TeaScenario.enabled_names()'
      ;;
    *tea_playbook_smoke_test.exs)
      NAMES_EXPR='Elmx.TestSupport.TemplateProject.tea_playbook_template_dirs()'
      ;;
  esac
  mapfile -t templates < <(
    cd "${ROOT}/${PKG}"
    MIX_ENV=test mix run --no-compile --no-start -e "
      ${NAMES_EXPR}
      |> Enum.each(&IO.puts/1)
    " 2>/dev/null
  )
fi

if [ "${#templates[@]}" -eq 0 ]; then
  echo "no templates selected for ${TEST_FILE}" >&2
  exit 2
fi

if ! [[ "${BATCH}" =~ ^[1-9][0-9]*$ ]]; then
  echo "ELMC_TEST_TEMPLATE_BATCH must be a positive integer (got: ${BATCH})" >&2
  exit 2
fi

passed=0
failed=()

run_mix_templates() {
  local joined="$1"
  shift
  # Remaining args are extra mix test flags (e.g. empty, or none).
  ELMC_HOST_SMOKE_TEMPLATE="${joined}" \
  ELMX_TEA_PLAYBOOK_TEMPLATE="${joined}" \
    "${ROOT}/scripts/mix-test-limited.sh" "${PKG}" "${TEST_FILE}" --include slow "$@"
}

# Join templates with commas for HostSmoke multi-select when batching.
run_batch() {
  local batch_templates=("$@")
  local joined
  joined="$(IFS=,; echo "${batch_templates[*]}")"
  printf '%s: %s … ' "${TEST_FILE}" "${joined}"
  if run_mix_templates "${joined}" >/dev/null 2>&1; then
    echo ok
    passed=$((passed + ${#batch_templates[@]}))
  else
    echo FAIL
    # Fall back to one-at-a-time to attribute failures.
    local t
    for t in "${batch_templates[@]}"; do
      printf '  retry %s … ' "${t}"
      if run_mix_templates "${t}" >/dev/null 2>&1; then
        echo ok
        passed=$((passed + 1))
      else
        echo FAIL
        failed+=("${t}")
        run_mix_templates "${t}" 2>&1 | tail -8 || true
      fi
    done
  fi
}

batch=()
for template in "${templates[@]}"; do
  batch+=("${template}")
  if [ "${#batch[@]}" -ge "${BATCH}" ]; then
    run_batch "${batch[@]}"
    batch=()
  fi
done
if [ "${#batch[@]}" -gt 0 ]; then
  run_batch "${batch[@]}"
fi

echo "---"
echo "passed=${passed} failed=${#failed[@]} batch=${BATCH}"
if [ "${#failed[@]}" -gt 0 ]; then
  printf '  %s\n' "${failed[@]}"
  exit 1
fi
