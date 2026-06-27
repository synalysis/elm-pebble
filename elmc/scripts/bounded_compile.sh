#!/usr/bin/env bash
# Run a heavy elmc compile in a memory- and time-bounded subprocess so host OOM
# kills this job instead of the IDE. Override limits via env vars.
set -euo pipefail

LIMIT_AS="${ELMC_COMPILE_AS_BYTES:-6000000000}"
TIMEOUT_SEC="${ELMC_COMPILE_TIMEOUT_SEC:-180}"

if [[ $# -lt 1 ]]; then
  echo "usage: bounded_compile.sh <project_dir> [extra mix run args...]" >&2
  exit 2
fi

PROJECT_DIR="$1"
shift

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

exec prlimit --as="${LIMIT_AS}" timeout "${TIMEOUT_SEC}" \
  mix run --no-start -e "
dir = Path.expand(\"${PROJECT_DIR}\", \"${ROOT}\")
out = System.get_env(\"ELMC_COMPILE_OUT\") || Path.join(System.tmp_dir!(), \"elmc-bounded-out\")
File.rm_rf!(out)
t0 = System.monotonic_time(:millisecond)
case Elmc.compile(dir, %{out_dir: out, entry_module: \"Main\", strip_dead_code: true}) do
  {:ok, _} ->
    IO.puts(:stderr, \"compile_ok in #{System.monotonic_time(:millisecond) - t0}ms -> #{out}\")
  other ->
    IO.puts(:stderr, \"compile_result=#{inspect(other)}\")
    System.halt(1)
end
" "$@"
