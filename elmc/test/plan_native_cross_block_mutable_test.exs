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

    assert step =~ "elmc_int_t plan_native_int_131 __attribute__((unused)) = 0;",
           "velocity bump temp must be a function-scope mutable local"

    refute step =~ "const elmc_int_t plan_native_int_131",
           "velocity bump temp must not be a skippable const before the join label"

    assert step =~ "plan_native_int_131 =",
           "expected an assignment into the hoisted velocity bump temp"

    # Truthy phi shape `compare` can name an arm temp at the join the same way.
    assert step =~ "elmc_int_t plan_native_int_32 __attribute__((unused)) = 0;",
           "truthy-phi arm temp must be hoisted when referenced from the join shape"

    refute step =~ "const elmc_int_t plan_native_int_32"
  end
end
