# Residual Dialyzer warnings for intentional runtime defenses Dialyzer cannot see
# (nil letrec_refs on partially-built plans; non-RC `*out` → `return` ABI).
# Covered by elmc default suite + watchface RC/TEA gates. Keep this list small.
[
  {"lib/elmc/backend/c/lower/function.ex", :guard_fail},
  {"lib/elmc/backend/c/lower/instr.ex", :pattern_match},
  {"lib/elmc/backend/c/lower/lambda.ex", :guard_fail},
  {"lib/elmc/backend/c_codegen/native/int.ex", :pattern_match}
]
