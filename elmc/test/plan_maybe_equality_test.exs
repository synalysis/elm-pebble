defmodule Elmc.PlanMaybeEqualityTest do
  @moduledoc """
  Regression: `Maybe a == / /=` must not lower through `elmc_as_int`.

  `elmc_as_int` returns 0 for Maybe tags, so `Nothing /= Just day` became
  `0 == 0` and YES `scheduleCompanionFetches` never requested sun/weather.
  """

  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.Compare
  alias Elmc.Test.CCodegenExtract
  alias Elmc.TestSupport.TemplateCompile

  test "Maybe Int /= Maybe Int selects :value compare mode" do
    b = Builder.new("Main", "needsFetch", args: ["lastKey", "dayKey"], rc_required: true)
    {last_reg, b} = Builder.fresh_reg(b)
    {day_reg, b} = Builder.fresh_reg(b)

    ctx =
      Context.new(
        module: "Main",
        function_name: "needsFetch",
        params: ["lastKey", "dayKey"],
        locals: %{"lastKey" => last_reg, "dayKey" => day_reg},
        local_types: %{"lastKey" => "Maybe Int", "dayKey" => "Maybe Int"}
      )

    assert {:ok, _reg, b2} =
             Compare.compile(
               %{
                 kind: :neq,
                 left: %{op: :var, name: "lastKey"},
                 right: %{op: :var, name: "dayKey"}
               },
               ctx,
               b
             )

    instrs =
      (b2.blocks ++ [b2.current_block])
      |> Enum.flat_map(& &1.instrs)

    compare = Enum.find(instrs, &match?(%{op: :compare}, &1))
    assert compare
    assert compare.args.mode == :value
  end

  test "watchface_yes scheduleCompanionFetches uses structural Maybe equality" do
    out = Path.join(System.tmp_dir!(), "yes-maybe-eq-gate-#{System.unique_integer([:positive])}")
    File.rm_rf!(out)

    assert {:ok, _} =
             TemplateCompile.compile_watch_template("watchface_yes",
               plan_ir_mode: :primary,
               plan_ir_strict: true,
               strip_dead_code: true,
               prune_runtime: true,
               prune_native_wrappers: true,
               pebble_int32: true,
               out_dir: out
             )

    body =
      out
      |> Path.join("c/elmc_generated.c")
      |> File.read!()
      |> CCodegenExtract.fn_impl_body("elmc_fn_Main_scheduleCompanionFetches")

    assert body =~ "elmc_value_equal("
    refute body =~ "elmc_as_int(owned[5]) == elmc_as_int(owned[7])"
    assert body =~ "ELMC_PEBBLE_CMD_COMPANION_SEND"

    # Mode-less compares (emit_test_maybe_just) default to :pointer and must not
    # call elmc_value_equal on native bools / int literals.
    generated = File.read!(Path.join(out, "c/elmc_generated.c"))
    refute generated =~ ~r/elmc_value_equal\(plan_native_bool_\d+,\s*0\)/
    refute generated =~ ~r/elmc_value_equal\(owned\[\d+\],\s*\d+\)/
  end
end
