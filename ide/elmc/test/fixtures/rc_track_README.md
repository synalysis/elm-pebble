# RC track probe fixtures

Host-side refcount probes for `elm/core` stdlib functions compiled through **elmc**.

## Layout

- One fixture project per module: `rc_track_<module>_project/`
- Probe module: `RcTrack<Module>Probe.elm` with nullary `probe*` functions
- Matrix registry: [`../support/rc_track_matrix.ex`](../support/rc_track_matrix.ex)
- Gate test: [`../generated_rc_track_core_gate_test.exs`](../generated_rc_track_core_gate_test.exs)

## Authoring probes

1. Add a row to [`../../docs/CODEGEN_COVERAGE_MATRIX.md`](../../docs/CODEGEN_COVERAGE_MATRIX.md) and `special_value_from_target` in the appropriate `special_values/*.ex` or `special_values/stdlib/*.ex` handler module.
2. Add a nullary `probeFoo : Int` (or heap-return type) to the fixture Elm module.
3. Register the probe in `RcTrackMatrix.@registry`.
4. Run `mix test.rc_gate` — it fails if matrix and probes drift.

### Naming

- Default: `List.reverse` → `probeReverse`
- Exceptions live in `RcTrackMatrix.@probe_exceptions` / `@matrix_probe_exceptions`
  - `Tuple.pair` → `probePair`
- `List.reverse` heap-return probe → `probeReverseList`
- `Process.*` probes live in the Task fixture with `probeSpawn` etc.

### Heap-return APIs

When the API returns a list (or other heap container), add a dedicated probe that **returns** that type and register it in `RcTrackMatrix.@heap_result_probes`. The harness releases the probe result explicitly.

Checksum `Int` probes are fine for most APIs; heap-return probes catch leaks codegen might hide when only the checksum is released.

### Variant probes (depth)

Beyond one happy-path probe per matrix function, add variants for high-risk paths:

- **Empty branches:** `Maybe`/`Result` Nothing/Err variants
- **Shared base / COW:** `probeInsertAlias`, `probeSetAlias`, record-update chains
- **Chained pipelines:** `probeAppendChain`, `probeConsChain`

Variants are listed in `RcTrackMatrix.@variant_probes` and included in module `@registry` probes but are not separate matrix rows.

### Passthrough / no-alloc

`Basics.identity`, `Basics.always`, and pure `Bitwise` ops still get probes; RC balance is expected to be trivial.

## Running tests

```bash
cd elmc
mix test.rc           # all @tag :rc_track
mix test.rc_2048      # game-2048 template + alloc probe + worker ownership gates
mix test.rc_gate      # matrix ↔ probe registry only
mix test.rc_stress    # 100-iteration subset (@tag :rc_track_stress)
mix test --only rc_track_core
mix test --only rc_track_fusion --include alloc_probe
```

## Fusion and worker ownership checklist

When touching `:rc_native` fusion or [`worker.ex`](../../lib/elmc/backend/worker.ex):

1. **New `:rc_native` fusion** — add a pattern fixture (different field/function names), an alloc probe harness (`@tag :rc_track_fusion`), and exercise the fusion through a second app/template via normal `update` → worker dispatch.
2. **Worker / ownership changes** — run `mix test.rc_2048`; add or extend a worker harness that checks model fields survive in-place pointer returns.
3. **RC thresholds** — never relax the catastrophic `rc_net >= 10` gate; document any other relaxation (for example Pebble small-int pool promotion allowing `max_update_rc_net <= 2` after move 10).
4. **PR question** — does this path return the same record pointer? If yes, is ownership transferred (not retain-then-release-result)?

## Limitations

`ELMC_RC_TRACK` balances `elmc_retain` / `elmc_release` on `ElmcValue` tags. It does **not** track raw `malloc` (Pebble scene buffers, etc.). App-level integration probes (e.g. 2048) cover those paths separately.
