# Elm-Style Diagnostics Phase 2 Backlog

Phase 1 implemented Elm-style diagnostics for tokenizer/parser flows. The remaining work below extends the same catalog + mapper approach to broader compiler diagnostics.

## Deferred Domains

- Type inference/type mismatch diagnostics from compiler check/build flows.
- Module/import/package resolution diagnostics.
- Runtime/formatter diagnostics not emitted by tokenizer/parser.
- Structured warning families (unused imports, dead code, naming warnings).

## Follow-Up Tasks

1. Expand the catalog with non-parser diagnostic families and stable IDs.
2. Add mapper coverage in `Ide.Compiler` and debugger ingestion paths.
3. Preserve structured message parts for richer UI rendering beyond plain text.
4. Add UI tests for LiveView diagnostics panel and editor tooltip rendering.
5. Add regression tests around `elmc` stderr parsing and embedded warning JSON payloads.

## Design Constraints To Preserve

- Keep existing `severity/source/message/line/column` fields backwards compatible.
- Version catalog updates so message drift is explicit and reviewable.
- Keep canonical atom-key diagnostic maps internally, convert only at API boundaries.
