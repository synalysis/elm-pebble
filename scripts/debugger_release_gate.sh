#!/usr/bin/env bash
# Full debugger release gate (automated checklist from IDE_ROADMAP / complete-debugger plan).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "== elmx unit tests =="
(cd "$ROOT/elmx" && mix test)

echo "== elmx coverage + audit gates =="
(cd "$ROOT/elmx" && mix test test/backend_coverage_gate_test.exs test/qualified_call_audit_test.exs test/phone_template_audit_test.exs)

echo "== IDE template compile gate =="
(cd "$ROOT/ide" && ELMX_TEMPLATE_COMPILE_GATE=1 mix test test/ide/mcp/debugger_template_compile_gate_test.exs --only template_compile_gate)

echo "== IDE template PBW gate =="
(cd "$ROOT/ide" && ELMC_TEMPLATE_PBW_GATE=1 mix test test/ide/template_pbw_gate_test.exs --only template_pbw_gate --max-cases 1)

echo "== IDE compiled_elixir corpus =="
(cd "$ROOT/ide" && ELMX_TEMPLATE_CORPUS=1 mix test --only compiled_elixir_corpus)

echo "== IDE MCP template corpus snapshots =="
(cd "$ROOT/ide" && mix test test/ide/mcp/debugger_template_corpus_test.exs --only template_corpus)

echo "== IDE MCP template corpus step snapshots =="
(cd "$ROOT/ide" && mix test test/ide/mcp/debugger_template_corpus_test.exs --only template_corpus_step)

echo "All debugger release gates passed."
