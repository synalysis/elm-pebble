# StoragePlan: layout contract for sequences and records

This document defines how elmc chooses runtime **layouts** for `List`, `Array`, and
plain record values, and when coercions are required.

## StoragePlan fields

A `StoragePlan` describes how a value is stored at runtime:

| Field | Values | Meaning |
|-------|--------|---------|
| `elem` | `{:primitive, :int \| :float}`, `{:record, mod, name}`, `{:boxed, :value}` | Element schema from IR types |
| `layout` | `:compact`, `:native_linked`, `:boxed_cons`, `:mixed` | Physical representation |
| `length` | `:known`, `:unknown` | Compile-time length knowledge |
| `access` | `:sequential`, `:random` | List vs Array surface semantics |

`:mixed` means callers may pass incompatible layouts; codegen may emit dual paths or
coercions at boundaries.

## Layouts

### Compact (`:compact`)

Random-access buffer. Used when length is known or all call sites agree on compact
input, and the element schema supports compact storage.

| Element | Runtime tag | Payload |
|---------|-------------|---------|
| `Int` | `ELMC_TAG_INT_LIST` | `elmc_int_t[]` |
| all-native record | `ELMC_TAG_RECORD_SEQ` | AoS struct array |
| boxed (future) | TBD | `ElmcValue*[]` |

`List Int` and `Array Int` share the same compact buffer when layout-compatible.

### Native linked (`:native_linked`)

Unknown-length producers (`List.filter`, dynamic `++`, etc.). Unboxed ints use
`ELMC_TAG_INT_SPINE`; boxed elements use `ELMC_TAG_LIST` cons cells.

### Boxed cons (`:boxed_cons`)

Fallback `ELMC_TAG_LIST` spine of `ElmcValue*`. Used when schema is unknown or
coercion to compact is impossible.

## Semantics (must hold for every layout)

### Equality

Elm `==` on lists is **structural**. Compact, native-linked, and boxed cons lists
with the same elements compare equal. Runtime equality helpers must dispatch on
layout or normalize before compare.

### Immutability

`Array.set` and record update follow Elm copy-on-write semantics. Compact buffers
are copied when updated; the original buffer is not mutated in place when shared.

### Sharing

- `Array.fromList` on a compact list: retain buffer (zero-copy) when layout matches.
- `Array.set` / `List.filter`: allocate new storage; do not mutate shared buffers.
- Immortal static lists (`emptyBoard`, etc.) remain immortal; compact copies are
  separate allocations.

## Coercion graph

```
Compact  ──widen──►  NativeLinked  ──widen──►  BoxedCons
   ▲                      ▲
   └── narrow (copy) ──────┘
```

| Transition | When | Cost |
|------------|------|------|
| Compact → NativeLinked | `filter`, unknown `++` consumer | O(n) copy or spine build |
| Compact → BoxedCons | platform escape, unknown consumer | O(n) |
| NativeLinked → Compact | proven length + all-native at boundary | O(n) |
| BoxedCons → Compact | `Array.fromList` on literal / repeat | O(n) or O(1) retain |

Coercions happen at **producers** and **API boundaries**, not inside every consumer
loop when analysis proves a single layout.

## Analysis

`LayoutSolver` performs fixed-point analysis over:

- function parameter call sites (with `let` binding context),
- record field writes,
- construct transfer rules (`layout_transfer.ex`).

Results are stored in `Process.put(:elmc_storage_plans, ...)` during codegen.

Schema metadata comes from `SchemaRegistry` (IR record aliases, `all_native?`,
field types). Import aliases are resolved in the lowerer only.

## Escape boundaries

These paths must dispatch on tag or box values:

- Pebble scene host list serialization (`serialize_list.ex`)
- Debugger value display
- Ports / JSON when not specialized
- Generic `List.map` with unknown function

When coercion is unsupported, emit diagnostic `elmc/layout` / `layout_coercion_required`.

## Out of scope (v1)

- Union tags inside compact arrays
- `List String` compact boxed sequences
- Nested `List (List Int)` SoA
- elmx parity (follow-up)
