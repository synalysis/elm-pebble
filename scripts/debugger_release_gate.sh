#!/usr/bin/env bash
# Full debugger release gate (automated checklist from IDE_ROADMAP / complete-debugger plan).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./ci-elmc-test-env.sh
. "${ROOT}/scripts/ci-elmc-test-env.sh"

echo "== elmx unit tests =="
"${ROOT}/scripts/mix-test-limited.sh" elmx

echo "== elmx coverage + audit gates =="
"${ROOT}/scripts/mix-test-limited.sh" elmx \
  test/backend_coverage_gate_test.exs \
  test/qualified_call_audit_test.exs \
  test/phone_template_audit_test.exs

echo "== IDE template compile gate =="
ELMX_TEMPLATE_COMPILE_GATE=1 \
  "${ROOT}/scripts/mix-test-limited.sh" ide \
  test/ide/mcp/debugger_template_compile_gate_test.exs --only template_compile_gate

echo "== IDE template PBW gate =="
ELMC_TEMPLATE_PBW_GATE=1 \
  "${ROOT}/scripts/mix-test-limited.sh" ide \
  test/ide/template_pbw_gate_test.exs --only template_pbw_gate

echo "== IDE compiled_elixir corpus =="
ELMX_TEMPLATE_CORPUS=1 \
  "${ROOT}/scripts/mix-test-limited.sh" ide --only compiled_elixir_corpus

echo "== IDE MCP template corpus snapshots =="
"${ROOT}/scripts/mix-test-limited.sh" ide \
  test/ide/mcp/debugger_template_corpus_test.exs --only template_corpus

echo "== IDE MCP template corpus step snapshots =="
"${ROOT}/scripts/mix-test-limited.sh" ide \
  test/ide/mcp/debugger_template_corpus_test.exs --only template_corpus_step

echo "All debugger release gates passed."
