#!/usr/bin/env bash
# Run plan_template_strict_gate_test.exs one template at a time.
#
# Usage:
#   ./scripts/mix-test-strict-gate.sh [template_name …]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "${ROOT}/scripts/mix-test-per-template.sh" test/plan_template_strict_gate_test.exs "$@"
