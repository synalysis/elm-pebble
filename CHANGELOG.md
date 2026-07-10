# Changelog

All notable changes to this project are documented in this file.

## [0.2.0] - 2026-07-10

### Added

- **Plan IR primary codegen** — reachable Elm functions lower to verified `%FunctionPlan{}`, then emit C (and optional bytecode) without legacy `ValueSlots` heuristics.
- **Readable plan C symbols** — `ELMC_PLAN_STATE_*` enums and `ELMC_UNION_*` macros replace magic block/tag integers in size-profile state-switch emit.
- **Module-qualified union ctor resolution** — ambiguous short names (`Up` vs `Pebble.Button.Up`) resolve via enclosing module context.
- **IDE size profile default** — watch compiles default to `codegen_profile: :size`; opt out with `optimize_for_size: false` in project settings.
- **Strict plan gate** — 21 watch templates compile with `plan_ir_strict: true` and zero `plan_primary_fallback` diagnostics.
- **Plan IR coverage docs** — `elmc/docs/PLAN_IR_COVERAGE.md` tracks generic lowering coverage and strict-pass templates.

### Fixed

- **State-switch union dispatch** — size-profile `switch_tag` uses peeled union tags (`elmc_union_tag_matches` / tag `switch`), not pointer-vs-integer compares.
- **Implicit fallthrough** — inner tag `switch` in plan state machines emits a trailing `break` for the outer `switch (__plan_state)`.
- **Companion shared-elm path** — template compile tests resolve `shared-elm` like the IDE (`starter_watch` strict gate).

### Changed

- **Codegen size optimizations** — native scalar returns, CFG cleanup, fusion-first routing, and smaller generated C for watch templates (e.g. 2048 ~48 KB → ~29 KB balanced → size).

[0.2.0]: https://github.com/synalysis/elm-pebble/compare/v0.1.0...v0.2.0
