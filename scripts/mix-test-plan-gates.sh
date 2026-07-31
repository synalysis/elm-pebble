#!/usr/bin/env bash
# Run plan-gate ExUnit files with per-template batching (and ulimit).
#
# Prefer this over `mix test.plan_gates`' old one-shot invocation, which could
# compile dozens of templates in a single BEAM and OOM / thrash the cache.
#
# Usage:
#   ./scripts/mix-test-plan-gates.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./ci-elmc-test-env.sh
. "${ROOT}/scripts/ci-elmc-test-env.sh"
export TEST_ULIMIT_V_KB="${TEST_ULIMIT_V_KB:-6291456}"
export ELIXIR_ERL_OPTIONS="${ELIXIR_ERL_OPTIONS:-+S 1:1 +MMscs 256}"

# HostSmoke-filtered full-template sweeps (batched inside mix-test-per-template).
PER_TEMPLATE_GATES=(
  test/plan_template_strict_gate_test.exs
  test/plan_reachable_coverage_test.exs
  test/bytecode_opcode_audit_test.exs
)

# Fixed/small template sets — one mix process each (TemplateCompile cached).
SINGLE_GATES=(
  test/plan_templates_primary_audit_test.exs
  test/plan_fusion_manifest_audit_test.exs
)

failed=0

for gate in "${PER_TEMPLATE_GATES[@]}"; do
  echo "==> per-template ${gate}"
  if ! "${ROOT}/scripts/mix-test-per-template.sh" "${gate}"; then
    failed=1
  fi
done

for gate in "${SINGLE_GATES[@]}"; do
  echo "==> limited ${gate}"
  if ! "${ROOT}/scripts/mix-test-limited.sh" elmc "${gate}" --include slow; then
    failed=1
  fi
done

if [ "${failed}" -ne 0 ]; then
  echo "plan gates: FAILED" >&2
  exit 1
fi

echo "plan gates: ok"
