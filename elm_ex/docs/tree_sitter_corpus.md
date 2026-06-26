# tree-sitter-elm test corpus

The [synalysis/tree-sitter-elm-test-corpus](https://github.com/synalysis/tree-sitter-elm-test-corpus) submodule at
`vendor/tree-sitter-elm-test-corpus` provides real-world Elm sources used to regression-test the `elm_ex` parser.

Both **elmc** and **elmx** share this frontend; parse gates run against `elm_ex` and are wired into CI for both toolchains.

## Layout

| Path | Purpose |
|------|---------|
| `vendor/tree-sitter-elm-test-corpus/` | Git submodule (pinned via `.lock`) |
| `elm_ex/test/support/tree_sitter_corpus.ex` | Discovery, size filter, parse gate |
| `elm_ex/docs/tree_sitter_corpus_baseline.json` | Minimum parse-ok regression floor |
| `elm_ex/scripts/sync_tree_sitter_corpus.sh` | Update submodule pin |

## Scope

- **Parse only** — files are not lowered or codegen'd (third-party packages lack `elm.json` deps).
- Import-first files without a `module` header infer a module name from the path (under `src/`, `examples/`, etc.).
- Files larger than **512 KiB** are skipped (generated test vectors, icon tables, etc.).
- Per-file timeout defaults to **10s** to avoid pathological hangs.

## Commands

```bash
# Update corpus pin
elm_ex/scripts/sync_tree_sitter_corpus.sh

# Fast smoke parse gate (~25 programs)
cd elm_ex && mix test.ts_corpus_smoke

# Full eligible parse gate (~20k programs, several minutes)
cd elm_ex && mix test.ts_corpus
```

Set `CORPUS_SKIP=1` or omit the submodule to skip corpus tests locally.

Override corpus location with `TREE_SITTER_CORPUS_DIR`, size limit with `TREE_SITTER_CORPUS_MAX_BYTES`, and timeout with `TREE_SITTER_CORPUS_TIMEOUT_MS`.
