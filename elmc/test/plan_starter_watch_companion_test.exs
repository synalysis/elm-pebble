defmodule Elmc.PlanStarterWatchCompanionTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Plan.Lower.Function
  alias Elmc.TestSupport.TemplateCompile

  @moduletag :slow

  test "requestWeather lowers companion send under plan-primary" do
    {:ok, result} =
      TemplateCompile.compile_watch_template("starter_watch",
        plan_ir_mode: :primary,
        plan_ir_strict: false,
        out_dir: Path.expand("tmp/plan_starter_watch", __DIR__)
      )

    decl_map = TemplateCompile.decl_map_from_result(result)
    decl = Map.fetch!(decl_map, {"Main", "requestWeather"})

    assert Map.has_key?(decl_map, {"Companion.Internal", "watchToPhoneTag"})
    assert {:ok, plan} = Function.lower(decl, "Main", decl_map, rc_required: true)
    dump = Elmc.Backend.Plan.Debug.dump(plan)
    assert dump =~ "watchToPhoneTag"
    assert dump =~ "watchToPhoneValue"
    assert dump =~ "ELMC_PEBBLE_CMD_COMPANION_SEND"
  end
end
