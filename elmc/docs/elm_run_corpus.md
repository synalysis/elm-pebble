# elm-run test corpus (Phase 0)

The [elm-run/test_corpus](https://github.com/elm-run/test_corpus) submodule at
`vendor/elm-run-test_corpus` provides small Elm programs used to regression-test
codegen.

## Layout

| Path | Purpose |
|------|---------|
| `vendor/elm-run-test_corpus/` | Git submodule (pinned via `.lock`) |
| `elmc/test/support/elm_run_corpus.ex` | Discovery, classification, compile gate |
| `elmc/test/fixtures/elm_run_corpus_index.json` | Generated index (tier per file) |
| `elmc/docs/elm_run_corpus_baseline.json` | Minimum elmc compile-ok regression floor |
| `elmc/docs/elm_run_corpus_elmx_baseline.json` | Minimum elmx compile-ok regression floor |
| `elmc/scripts/sync_test_corpus.sh` | Update submodule + regenerate index |

## Tiers

- `compile_candidate` — portable `elm/core` programs without gold stdout
- `run_scalar` / `run_structured` — same, with `.expected` output (execution tier: Phase 1)
- `elm_run_only` — imports outside `elm/core` or sibling modules
- `compile_error_expected` — metadata says compile/run should fail
- `skip` — explicit skip in corpus metadata

## Commands

```bash
# Update corpus pin + index
elmc/scripts/sync_test_corpus.sh

# Regenerate index only
cd elmc && mix test.corpus_index

# Fast canary compile gate (~20 programs, runs in default mix test)
cd elmc && mix test.corpus_smoke

# Full portable elmc compile gate (~629 programs, ~2 min; 45s per-program timeout)
cd elmc && mix test.corpus

# elmx portable compile smoke (~23 canary programs)
cd elmc && mix test.corpus_elmx_smoke

# Full portable elmx compile gate (~629 programs, ~1 min; 30s per-program timeout)
cd elmc && mix test.corpus_elmx

# Fixture codegen dual-backend gate (elmc + elmx on template fixtures)
cd elmc && mix test.fixture_codegen

# Execution smoke against corpus .expected gold (~7 programs)
cd elmc && mix test.corpus_run_smoke

# Full execution gates for elmc and elmx (~395 programs each)
cd elmc && mix test.corpus_run

# elmc/elmx output parity on execution smoke (when both succeed)
cd elmc && mix test.corpus_parity
```

Parity smoke currently uses `Basics/DecTest.elm` only — expand as backends converge.

Set `CORPUS_SKIP=1` or omit the submodule to skip corpus tests locally.

Override corpus location with `ELM_RUN_CORPUS_DIR`.

## See also

- [tree-sitter-elm parse corpus](../elm_ex/docs/tree_sitter_corpus.md) — real-world Elm sources for parser regression (~20k files).
