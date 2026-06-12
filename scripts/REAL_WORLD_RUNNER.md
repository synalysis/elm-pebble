# Real-World Elm Package Runner

This runner exercises public Elm packages against both compilers:

- `elmc`
- `elmx`

It is resumable and stores progress under:

- `tmp/real_world_elm_runner/state.json`
- `tmp/real_world_elm_runner/todos.json`
- `tmp/real_world_elm_runner/reports/*.json`
- downloaded package cache in `tmp/real_world_elm_runner/packages/`

## Usage

From repo root:

```bash
python3 scripts/real_world_elm_runner.py --repo-root . --limit 25
```

Compiler escripts are built automatically (`mix escript.build` in `elmc/` and `elmx/`) when missing. To require pre-built binaries:

```bash
python3 scripts/real_world_elm_runner.py --repo-root . --no-build-escripts --limit 25
```

Run strictly against already installed local packages (no remote registry fetch, no `elm install` prompts):

```bash
python3 scripts/real_world_elm_runner.py \
  --repo-root . \
  --local-packages-dir ~/.elm/0.19.1/packages \
  --local-cache-only \
  --limit 25
```

Check-only mode (skip doc-snippet runtime evaluation):

```bash
python3 scripts/real_world_elm_runner.py \
  --repo-root . \
  --local-cache-only \
  --skip-runtime \
  --limit 25
```

Start over from package 1 and clear todo/status artifacts:

```bash
python3 scripts/real_world_elm_runner.py --repo-root . --reset --limit 25
```

Resume from a specific package:

```bash
python3 scripts/real_world_elm_runner.py --repo-root . --start-from-package elm/json --limit 10
```

## Parse-all scorecard (in-repo + optional local packages)

The ExUnit gate in `elmc/test/parse_all_scorecard_test.exs` scans in-repo fixtures on every `mix test`. To include locally installed `elm/*` package sources as a supplemental corpus:

```bash
cd elmc
ELMC_PARSE_ALL_INCLUDE_PACKAGE_CACHE=1 mix test test/parse_all_scorecard_test.exs
```

Artifacts: `elmc/test/tmp/parse_all/scorecard.{json,md}`

## Current behavior

For each package:

1. Fetch package metadata from [package.elm-lang.org](https://package.elm-lang.org/) (or read from local cache).
2. Skip packages that depend on browser/http-related families (`elm/browser`, `elm/http`, etc.).
3. Install and cache package source locally.
4. Run:
   - `elmc check <package_dir>`
   - `elmx check <package_dir>`
5. If docs include Elm code blocks, generate a synthetic doctest module and compile-check it with both compilers.
6. Record failures in `todos.json`.

### Special handling for `elm/core`

- `elm/core` is handled as a dedicated docs/runtime suite instead of regular package-source download.
- The runner builds a local synthetic project from `elm/core` docs snippets and validates it with `elmc` and `elmx`.
- Runtime evaluation requires `scripts/doc_snippet_runtime_eval.exs` (skipped gracefully when absent).

## Notes

- Doctest runtime comparison is skipped when `scripts/doc_snippet_runtime_eval.exs` is not present.
- Packages are cached and preserved so reruns continue after the last processed package.
- In local-cache mode, package metadata/docs are read from the local package directory first.
- Historical `todos.json` entries may reference the old `elm_executor` engine name.
