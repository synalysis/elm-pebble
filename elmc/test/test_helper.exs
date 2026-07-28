ExUnit.start()

Application.put_env(:elmc, :default_plan_ir_mode, :primary)
Application.put_env(:elmc, :default_plan_ir_strict, true)

ExUnit.configure(
  exclude: [
    # Heavy template / wasm / plan-surface suites — opt in via `mix test.slow`
    # or `--include slow` / `--only slow`.
    :slow,
    :corpus,
    :corpus_run,
    :corpus_elmx,
    :corpus_index,
    :fixture_codegen,
    :plan_shadow,
    :plan_parity,
    :plan_rc_track_exec
  ]
)
