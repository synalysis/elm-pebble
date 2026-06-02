# elm/core Parity Matrix

This matrix tracks the implementation mode and current parity status for eligible `elm/core` modules.

| Module | Mode | Status | Notes |
| --- | --- | --- | --- |
| Array | runtime intrinsic + lowered wrappers | compliance | `CoreCompliance` + `stdlib_qualified_emit_test`; list-backed; negative `get` → `Nothing`. |
| Basics | runtime intrinsic + lowered operators | compliance | `modBy`/min/max/clamp via emit; trig via `Core.Math` emit; `isNaN`/`isInfinite` helpers. |
| Bitwise | runtime intrinsic | compliance | `Core.Bitwise` + `bitwiseExtras` unsigned `shiftRightZfBy` vs elmc. |
| Char | runtime intrinsic | compliance | `fromCode`/`toCode` roundtrip; `toUpper`/`toLower` via `Core.Chars` emit. |
| Debug | runtime intrinsic | compliance | `debugEcho` via `Core.Debug.log`; `toString` formats ctor/list/record shapes. |
| Dict | lowered + runtime intrinsic | compliance | `Core.Collections` list-backed dict; `CoreCompliance` dict/set suite green. |
| List | lowered + runtime intrinsic | compliance | Core list helpers + fold/map/sort/sortBy/sortWith via `Core` + `list_stdlib_emit_test.exs`. |
| Result | lowered | compliance | `CoreCompliance` maybe/result/nested case; combinators via `Core`/`Stdlib`. |
| Set | lowered + runtime intrinsic | compliance | `Core.Collections` list-backed set; duplicate-key semantics in compliance tests. |
| String | runtime intrinsic | compliance | append/length/isEmpty in compliance + qualified emit tests. |
| Task | runtime intrinsic (scheduler bridge) | compliance | `Task.succeed`/`fail` + nested tasks in compliance; no real scheduler. |
| Time | runtime intrinsic + Pebble tick bridge | compliance | `now`/`here` via runtime helpers; `Time.every` / `Frame.every` subscription masks in `subscription_masks.ex`. |
| Tuple | lowered + runtime intrinsic | compliance | pair/first/second + flat tagged union ctor case patterns. |

## Compliance gates

- `elmx/test/core_compliance_runtime_test.exs` — full `CoreCompliance` module (61 functions) compile + execute.
- `elmx/test/core_compliance_ir_test.exs` — no residual `:unsupported` bodies after `let` layout fix.
- `elmx/test/stdlib_qualified_emit_test.exs` — `Dict`/`Set`/`Array`/`Bitwise`/`Task`/`Process` qualified emit paths.
- `elmx/test/runtime_generator_parity_test.exs` — all 249 `elmc_*` symbols from `c_codegen`.

## Mode Definitions

- **lowered**: implemented through general Elm lowering/codegen.
- **runtime intrinsic**: implemented in C runtime helper functions.
- **wrapper**: shallow lowering mapped to either lowered/intrinsic implementation.
