#!/usr/bin/env bash
# Tight typespecs campaign — run from repo root.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Making package lib/*.ex writable"
find elm_ex/lib elmc/lib elmx/lib ide/lib -type f -name '*.ex' -exec chmod u+w {} +

echo "==> Phase 1: inject missing @spec"
for pkg in elm_ex elmc elmx ide; do
  python3 scripts/inject-typespecs.py --package "$pkg" --mode inject
done

echo "==> Cleanup junk / trailing aliases"
python3 scripts/remove-junk-specs.py
python3 scripts/fix-trailing-aliases.py
python3 scripts/remove-unused-types-alias.py

echo "==> Audit"
python3 scripts/audit-typespecs.py --fail-on-gaps

echo "==> Compile (warnings as errors)"
for pkg in elm_ex elmc elmx ide; do
  echo "--- $pkg ---"
  (cd "$pkg" && mix compile --warnings-as-errors)
done

echo "==> Done"
