# elm/core Parity Matrix

This matrix tracks the implementation mode and current parity status for eligible `elm/core` modules.

| Module | Mode | Status | Notes |
| --- | --- | --- | --- |
| Array | runtime intrinsic + lowered wrappers | in progress | Backed by list runtime currently; needs semantic/perf parity work. |
| Basics | runtime intrinsic + lowered operators | in progress | Added core min/max/clamp/modBy; float/trig/parity still pending. |
| Bitwise | runtime intrinsic | in progress | Added `complement`; shift semantics still need full Elm parity validation. |
| Char | runtime intrinsic | in progress | `toCode`/`fromCode` path exists; case transforms still pending. |
| Debug | runtime intrinsic | in progress | Added `toString`; richer Elm-like rendering pending. |
| Dict | lowered + runtime intrinsic | in progress | Current runtime uses list-backed representation; needs faithful structure parity. |
| List | lowered + runtime intrinsic | in progress | Core list helpers exist; sorting/mapN parity pending. |
| Result | lowered | in progress | Constructors/combinators compile; broader semantic tests pending. |
| Set | lowered + runtime intrinsic | in progress | List-backed currently; faithful set semantics pending. |
| String | runtime intrinsic | in progress | append/isEmpty/length done; full API parity pending. |
| Task | runtime intrinsic (scheduler bridge) | in progress | `succeed`/`fail` bridged via runtime; scheduler/effects model pending. |
| Time | runtime intrinsic + Pebble tick bridge | in progress | `now`/`here` use runtime clock+offset helpers; `every` currently maps to Pebble second-tick cadence. |
| Tuple | lowered + runtime intrinsic | in progress | pair/first/second paths present; map helpers pending. |

## Mode Definitions

- **lowered**: implemented through general Elm lowering/codegen.
- **runtime intrinsic**: implemented in C runtime helper functions.
- **wrapper**: shallow lowering mapped to either lowered/intrinsic implementation.
