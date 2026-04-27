#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ELMC_DIR="${ROOT_DIR}/elmc"
CORE_TESTS_DIR="${ROOT_DIR}/core-1.0.5/tests"
OUT_DIR="${ELMC_DIR}/tmp/core-oracle"
ELM_JSON="${OUT_DIR}/elm-test.json"
ELMC_LOG="${OUT_DIR}/elmc-core.log"
REPORT_MD="${OUT_DIR}/report.md"

RUN_ELM=1
RUN_ELMC=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-elm)
      RUN_ELM=0
      shift
      ;;
    --skip-elmc)
      RUN_ELMC=0
      shift
      ;;
    *)
      echo "unknown argument: $1" >&2
      echo "usage: $0 [--skip-elm] [--skip-elmc]" >&2
      exit 2
      ;;
  esac
done

mkdir -p "${OUT_DIR}"

ELM_STATUS=0
ELMC_STATUS=0

if [[ ${RUN_ELM} -eq 1 && ! -d "${CORE_TESTS_DIR}" ]]; then
  echo "[core-oracle] ${CORE_TESTS_DIR} not found, skipping official elm/core suite"
  RUN_ELM=0
fi

if [[ ${RUN_ELM} -eq 1 ]]; then
  echo "[core-oracle] running official elm/core test suite via elm-test..."
  (
    cd "${CORE_TESTS_DIR}"
    ./run-tests.sh --report=json > "${ELM_JSON}"
  ) || ELM_STATUS=$?
  echo "[core-oracle] elm-test exit code: ${ELM_STATUS}"
fi

if [[ ${RUN_ELMC} -eq 1 ]]; then
  echo "[core-oracle] running elmc core conformance tests..."
  (
    cd "${ELMC_DIR}"
    mix test test/core_compliance_test.exs test/core_differential_conformance_test.exs --trace --color > "${ELMC_LOG}"
  ) || ELMC_STATUS=$?
  echo "[core-oracle] elmc exit code: ${ELMC_STATUS}"
fi

echo "[core-oracle] generating differential summary report..."
python3 "${ELMC_DIR}/scripts/compare_core_oracle.py" \
  --elm-json "${ELM_JSON}" \
  --elmc-log "${ELMC_LOG}" \
  --out "${REPORT_MD}" || true

echo "[core-oracle] artifacts:"
echo "  - ${ELM_JSON}"
echo "  - ${ELMC_LOG}"
echo "  - ${REPORT_MD}"

if [[ ${RUN_ELM} -eq 1 && ${ELM_STATUS} -ne 0 ]]; then
  echo "[core-oracle] official elm/core test run failed" >&2
  exit 1
fi

if [[ ${RUN_ELMC} -eq 1 && ${ELMC_STATUS} -ne 0 ]]; then
  echo "[core-oracle] elmc core conformance tests failed" >&2
  exit 1
fi

echo "[core-oracle] both selected runs completed successfully"
