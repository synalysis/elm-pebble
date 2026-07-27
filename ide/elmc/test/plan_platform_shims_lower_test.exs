defmodule Elmc.PlanPlatformShimsLowerTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Plan.Lower.Function
  alias Elmc.TestSupport.TemplateCompile

  @moduletag :plan_surface
  @moduletag :slow

  setup do
    {:ok, result} =
      TemplateCompile.compile_watch_template("game_elmtris", plan_ir_mode: :shadow)

    Process.put(:elmc_constructor_tags, Elmc.Backend.CCodegen.IRQueries.constructor_tag_map(result.ir))

    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    decl_map = TemplateCompile.decl_map_from_result(result)

    {:ok, decl_map: decl_map}
  end

  test "lowers Pebble.Events.batch kernel alias", %{decl_map: decl_map} do
    decl = Map.fetch!(decl_map, {"Pebble.Events", "batch"})

    assert {:ok, plan} = Function.lower(decl, "Pebble.Events", decl_map, rc_required: false)
    dump = Elmc.Backend.Plan.Debug.dump(plan)
    assert dump =~ "const_int"
    assert :ok = Elmc.Backend.Plan.Verify.run(plan)
  end

  test "lowers Pebble.Ui.Color.toInt as color identity", %{decl_map: decl_map} do
    decl = Map.fetch!(decl_map, {"Pebble.Ui.Color", "toInt"})

    assert {:ok, plan} = Function.lower(decl, "Pebble.Ui.Color", decl_map, rc_required: false)
    dump = Elmc.Backend.Plan.Debug.dump(plan)
    assert dump =~ "load_param"
    refute dump =~ "switch_ctor_tag"
    assert :ok = Elmc.Backend.Plan.Verify.run(plan)
  end

  test "lowers Pebble.Light.enable backlight cmd", %{decl_map: decl_map} do
    decl = Map.fetch!(decl_map, {"Pebble.Light", "enable"})

    assert {:ok, plan} = Function.lower(decl, "Pebble.Light", decl_map, rc_required: false)
    dump = Elmc.Backend.Plan.Debug.dump(plan)
    assert dump =~ "cmd_backlight_from_maybe"
    assert :ok = Elmc.Backend.Plan.Verify.run(plan)
  end
end
