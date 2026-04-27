# Real-World Elm Package Runner

This runner exercises public Elm packages against both compilers:

- `elmc`
- `elm_executor`

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

Run strictly against already installed local packages (no remote registry fetch, no `elm install` prompts):

```bash
python3 scripts/real_world_elm_runner.py \
  --repo-root . \
  --local-packages-dir ~/.elm/0.19.1/packages \
  --limit 25
```

Start over from package 1 and clear todo/status artifacts:

```bash
python3 scripts/real_world_elm_runner.py --repo-root . --reset --limit 25
```

## Current behavior

For each package:

1. Fetch package metadata from [package.elm-lang.org](https://package.elm-lang.org/).
2. Skip packages that depend on browser/http-related families (`elm/browser`, `elm/http`, etc.).
3. Install and cache package source locally.
4. Run:
   - `elmc check <package_dir>`
   - `elm_executor check <package_dir>`
5. If docs include Elm code blocks, generate a synthetic doctest module and compile-check it with both compilers.
6. Record failures in `todos.json`.

### Special handling for `elm/core`

- `elm/core` is handled as a dedicated docs/runtime suite instead of regular package-source download.
- The runner builds a local synthetic project from `elm/core` docs snippets and validates it with `elmc` and `elm_executor`.
- Runtime value comparison uses the in-repo evaluator pipeline (no JavaScript execution).

## Notes

- Doctest handling is currently **compile-check only**. Runtime output assertions are tracked as TODO work.
- Packages are cached and preserved so reruns continue after the last processed package.
- In local-cache mode, package metadata/docs are read from the local package directory first.
