ExUnit.start()

Application.put_env(:elmc, :default_plan_ir_mode, :primary)

ExUnit.configure(
  exclude: [
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
