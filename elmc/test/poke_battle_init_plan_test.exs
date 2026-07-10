defmodule Elmc.PokeBattleInitPlanTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Plan.Lower.Function, as: PlanLower
  alias Elmc.TestSupport.TemplateCompile

  @moduletag :slow

  test "watchface_poke_battle Main.init lowers under plan_ir_strict primary" do
    out_dir = Path.expand("tmp/poke_battle_init_plan", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, result} =
             TemplateCompile.compile_watch_template("watchface_poke_battle",
               plan_ir_mode: :primary,
               plan_ir_strict: true,
               out_dir: out_dir
             )

    decl_map = TemplateCompile.decl_map_from_result(result)
    init = Map.fetch!(decl_map, {"Main", "init"})

    assert {:ok, _plan} = PlanLower.lower(init, "Main", decl_map, rc_required: true)

    refute Enum.any?(result.layout_coercion_diagnostics, fn diag ->
             diag["code"] == "plan_primary_fallback" and
               String.contains?(diag["message"] || "", "Main.init")
           end)
  end
end
