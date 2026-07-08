#!/usr/bin/env bash
# Run corpus execution probes one program per BEAM process (memory-safe).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export TEST_ULIMIT_V_KB="${TEST_ULIMIT_V_KB:-4194304}"
export ELIXIR_ERL_OPTIONS="${ELIXIR_ERL_OPTIONS:-+S 1:1 +MMscs 256}"
export MIX_ENV="${MIX_ENV:-test}"

fail=0
pass=0

for rel in "$@"; do
  echo "== corpus probe ${rel} =="
  set +e
  line="$(
    CORPUS_PATH="${rel}" "${ROOT}/scripts/mix-run-limited.sh" elmc -e '
      Application.put_env(:elmc, :default_plan_ir_mode, :off)
      alias Elmc.Test.ElmRunCorpus
      path = System.get_env("CORPUS_PATH")
      tmp = "test/tmp/corpus_path_probe/"
      gold = ElmRunCorpus.read_expected!(path)
      case ElmRunCorpus.run_elmc_execution!(path, tmp, timeout_ms: 60_000) do
        {:ok, got} ->
          cond do
            got == gold -> IO.puts("OK")
            true -> IO.puts("MISMATCH " <> inspect(gold) <> " " <> inspect(got))
          end
        err -> IO.puts("FAIL " <> inspect(err))
      end
    ' 2>&1 | tail -1
  )"
  code=$?
  set -e
  echo "${line}"
  if [[ "${code}" -eq 0 && "${line}" == OK ]]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
  fi
done

echo "done pass=${pass} fail=${fail}"
exit "$(test "${fail}" -eq 0 && echo 0 || echo 1)"
