#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ELMC_DIR="${ROOT_DIR}/elmc"
BASELINE_JSON="${ELMC_DIR}/docs/conformance_baseline.json"
CURRENT_JSON="${ELMC_DIR}/test/tmp/conformance/scorecard.json"
REPORT_MD="${ELMC_DIR}/test/tmp/conformance/guardrail_report.md"

# shellcheck source=../ci-elmc-test-env.sh
. "${ROOT_DIR}/scripts/ci-elmc-test-env.sh"

echo "[conformance-guardrails] generating current scorecard..."
"${ROOT_DIR}/scripts/mix-test-limited.sh" elmc test/conformance_scorecard_test.exs

echo "[conformance-guardrails] comparing with baseline..."
python3 "${ELMC_DIR}/scripts/compare_conformance_scorecard.py" \
  --baseline "${BASELINE_JSON}" \
  --current "${CURRENT_JSON}" \
  --out "${REPORT_MD}"

echo "[conformance-guardrails] report: ${REPORT_MD}"
echo "[conformance-guardrails] status: PASS"
