defmodule Elmc.PlanNativeCrossBlockMutableTest do
  @moduledoc """
  Goto CFG must hoist native ints used across blocks (e.g. native_int_phi shapes at
  a join) as mutable locals. A `const` def skipped by `goto join` triggers
  `-Werror=maybe-uninitialized` on Pebble builds (game-jump-n-run `Main.step`).
  """

  use ExUnit.Case, async: false

  alias Elmc.TestSupport.TemplateCompile

  test "game-jump-n-run Main.step hoists cross-block velocity bump as mutable local" do
    out_dir = Path.expand("tmp/plan_native_cross_block_jump", __DIR__)

    assert {:ok, _result} =
             TemplateCompile.compile_watch_template("game_jump_n_run",
               codegen_profile: :size,
               plan_ir_mode: :primary,
               out_dir: out_dir
             )

    c =
      out_dir
      |> Path.join("c/elmc_generated.c")
      |> File.read!()

    step =
      case Regex.run(
             ~r/static __attribute__\(\(noinline, noclone\)\) RC elmc_fn_Main_step\(ElmcValue \*\*out, ElmcValue \*model\) \{.*?^\}/ms,
             c
           ) do
        [body] -> body
        _ -> flunk("elmc_fn_Main_step definition not found in generated C")
      end

    # Velocity bump: `vy + 1` assigned before a join, then read at the join for clamp.
    # Reg ids shift with plan lowering; assert the hoist pattern, not a fixed number.
    assert [_, bump_reg] =
             Regex.run(~r/plan_native_int_(\d+) = plan_native_int_\d+ \+ 1;/, step),
           "expected velocity bump `plan_native_int_N = … + 1` before a join:\n#{step}"

    assert step =~ "elmc_int_t plan_native_int_#{bump_reg} __attribute__((unused)) = 0;",
           "velocity bump temp plan_native_int_#{bump_reg} must be a function-scope mutable local"

    refute step =~ "const elmc_int_t plan_native_int_#{bump_reg}",
           "velocity bump temp must not be a skippable const before the join label"

    # Truthy phi shape `compare` can name an arm temp at the join the same way.
    assert step =~ "elmc_int_t plan_native_int_32 __attribute__((unused)) = 0;",
           "truthy-phi arm temp must be hoisted when referenced from the join shape"

    refute step =~ "const elmc_int_t plan_native_int_32"
  end
end
