#!/usr/bin/env bash
# Run corpus execution probes one program per BEAM process (memory-safe).
# Usage: ./scripts/corpus-probe-paths.sh [elmc|elmx] <rel/path.elm> ...
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export TEST_ULIMIT_V_KB="${TEST_ULIMIT_V_KB:-4194304}"
export ELIXIR_ERL_OPTIONS="${ELIXIR_ERL_OPTIONS:-+S 1:1 +MMscs 256}"
export MIX_ENV="${MIX_ENV:-test}"

backend="elmc"
if [[ "${1:-}" == "elmc" || "${1:-}" == "elmx" ]]; then
  backend="$1"
  shift
fi

fail=0
pass=0

run_fn="run_elmc_execution!"
if [[ "${backend}" == "elmx" ]]; then
  run_fn="run_elmx_execution!"
fi

for rel in "$@"; do
  echo "== corpus probe ${backend} ${rel} =="
  set +e
  line="$(
    CORPUS_PATH="${rel}" CORPUS_RUN_FN="${run_fn}" "${ROOT}/scripts/mix-run-limited.sh" elmc -e '
      Application.put_env(:elmc, :default_plan_ir_mode, :primary)
      alias Elmc.Test.ElmRunCorpus
      path = System.get_env("CORPUS_PATH")
      run_fn = System.get_env("CORPUS_RUN_FN")
      tmp = "test/tmp/corpus_path_probe/"
      gold = ElmRunCorpus.read_expected!(path)
      result =
        case run_fn do
          "run_elmx_execution!" -> ElmRunCorpus.run_elmx_execution!(path, tmp, timeout_ms: 60_000)
          _ -> ElmRunCorpus.run_elmc_execution!(path, tmp, timeout_ms: 60_000)
        end
      case result do
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
