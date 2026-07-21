#!/usr/bin/env bash
# Validate git-tracked application elm.json files for fields required by Elm 0.19.1.
# Missing test-dependencies causes official `elm make` to hang at 100% CPU.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

skip_re='editor-deps-invalid-json'
failed=0

while IFS= read -r path; do
  [[ "$path" == *"$skip_re"* ]] && continue

  python3 - "$path" <<'PY' || { failed=1; continue; }
import json, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
if data.get("type") != "application":
    sys.exit(0)
issues = []
if "test-dependencies" not in data:
    issues.append("missing test-dependencies")
direct = data.get("dependencies", {}).get("direct", {})
if "elm/json" not in direct:
    issues.append("missing dependencies.direct[\"elm/json\"]")
if issues:
    print(f"{path}: {', '.join(issues)}", file=sys.stderr)
    sys.exit(1)
PY
done < <(git ls-files '**/elm.json')

if [[ "$failed" -ne 0 ]]; then
  echo "elm.json validation failed (see above)." >&2
  exit 1
fi

echo "All tracked application elm.json files are valid."
