defmodule Elmc.PlanShadowCoverageTest do
  use ExUnit.Case, async: false

  @moduletag :plan_shadow

  @fixture Path.expand("fixtures/simple_project", __DIR__)

  setup do
    {:ok, result} =
      Elmc.compile(@fixture, %{
        out_dir: Path.expand("tmp/plan_coverage_codegen", __DIR__),
        entry_module: "Main",
        strip_dead_code: true
      })

    Process.put(:elmc_constructor_tags, Elmc.Backend.CCodegen.IRQueries.constructor_tag_map(result.ir))

  decl_map =
      result.ir.modules
      |> Enum.flat_map(fn mod ->
        mod.declarations
        |> Enum.filter(&(&1.kind == :function))
        |> Enum.map(fn decl -> {{mod.name, decl.name}, decl} end)
      end)
      |> Map.new()

    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    {:ok, decl_map: decl_map}
  end

  test "lowers Main.update tagged Msg case", %{decl_map: decl_map} do
    decl = Map.fetch!(decl_map, {"Main", "update"})

    assert {:ok, plan} = Elmc.Backend.Plan.Lower.Function.lower(decl, "Main", decl_map, rc_required: true)
    assert length(plan.blocks) >= 4
    dump = Elmc.Backend.Plan.Debug.dump(plan)
    refute dump =~ "switch_ctor_tag"
    assert dump =~ "switch_tag"
    assert :ok = Elmc.Backend.Plan.Verify.run(plan)
  end

  test "lowers Main.init with cmd batch tuple", %{decl_map: decl_map} do
    decl = Map.fetch!(decl_map, {"Main", "init"})

    assert {:ok, plan} = Elmc.Backend.Plan.Lower.Function.lower(decl, "Main", decl_map, rc_required: true)
    dump = Elmc.Backend.Plan.Debug.dump(plan)
    assert dump =~ "cmd_batch"
    assert dump =~ "tuple2"
    assert :ok = Elmc.Backend.Plan.Verify.run(plan)
  end

  test "lowers Main.handleAppMsg tagged case with arithmetic", %{decl_map: decl_map} do
    decl = Map.fetch!(decl_map, {"Main", "handleAppMsg"})

    assert {:ok, plan} = Elmc.Backend.Plan.Lower.Function.lower(decl, "Main", decl_map, rc_required: true)
    dump = Elmc.Backend.Plan.Debug.dump(plan)
    refute dump =~ "switch_ctor_tag"
    assert dump =~ "int_arith"
    assert dump =~ "maybe_just_own"
    assert :ok = Elmc.Backend.Plan.Verify.run(plan)
  end

  test "lowers Main.handlePlatformMsg with pebble cmds", %{decl_map: decl_map} do
    decl = Map.fetch!(decl_map, {"Main", "handlePlatformMsg"})

    assert {:ok, plan} = Elmc.Backend.Plan.Lower.Function.lower(decl, "Main", decl_map, rc_required: true)
    dump = Elmc.Backend.Plan.Debug.dump(plan)
    refute dump =~ "switch_ctor_tag"
    assert dump =~ "pebble_cmd"
    assert :ok = Elmc.Backend.Plan.Verify.run(plan)
  end

  test "lowers Main.requestSystemInfo cmd batch with partial constructors", %{decl_map: decl_map} do
    decl = Map.fetch!(decl_map, {"Main", "requestSystemInfo"})

    assert {:ok, plan} = Elmc.Backend.Plan.Lower.Function.lower(decl, "Main", decl_map, rc_required: true)
    dump = Elmc.Backend.Plan.Debug.dump(plan)
    assert dump =~ "cmd_batch"
    assert :ok = Elmc.Backend.Plan.Verify.run(plan)
  end

  test "lowers Main.counterDraw with render_cmd", %{decl_map: decl_map} do
    decl = Map.fetch!(decl_map, {"Main", "counterDraw"})

    assert {:ok, plan} = Elmc.Backend.Plan.Lower.Function.lower(decl, "Main", decl_map, rc_required: false)
    assert Elmc.Backend.Plan.Debug.dump(plan) =~ "render_cmd"
    assert :ok = Elmc.Backend.Plan.Verify.run(plan)
  end

  test "lowers Main.subscriptions with pebble_sub batch", %{decl_map: decl_map} do
    decl = Map.fetch!(decl_map, {"Main", "subscriptions"})

    assert {:ok, plan} = Elmc.Backend.Plan.Lower.Function.lower(decl, "Main", decl_map, rc_required: false)
    assert Elmc.Backend.Plan.Debug.dump(plan) =~ "pebble_sub"
    assert :ok = Elmc.Backend.Plan.Verify.run(plan)
  end

  test "lowers Main.view ui tree", %{decl_map: decl_map} do
    decl = Map.fetch!(decl_map, {"Main", "view"})

    assert {:ok, plan} = Elmc.Backend.Plan.Lower.Function.lower(decl, "Main", decl_map, rc_required: false)
    dump = Elmc.Backend.Plan.Debug.dump(plan)
    assert dump =~ "render_cmd" or dump =~ "tuple2"
    assert :ok = Elmc.Backend.Plan.Verify.run(plan)
  end

  test "lowers Main.counterOf field access", %{decl_map: decl_map} do
    decl = Map.fetch!(decl_map, {"Main", "counterOf"})

    assert {:ok, _plan} =
             Elmc.Backend.Plan.Lower.Function.lower(decl, "Main", decl_map, rc_required: false)
  end

  test "shadow stats track verified functions" do
    Elmc.Backend.Plan.reset_shadow_stats()

    decl = %{name: "zero", args: [], expr: %{op: :int_literal, value: 0}}

    assert :ok =
             Elmc.Backend.Plan.shadow_verify(decl, "Main", %{},
               plan_ir_mode: :shadow,
               rc_required: false
             )

    assert %{ok: 1} = Map.take(Elmc.Backend.Plan.shadow_stats(), [:ok])
  end

  test "simple_project Main functions lower under shadow", %{decl_map: decl_map} do
    names = [
      "init",
      "update",
      "handleAppMsg",
      "handlePlatformMsg",
      "counterOf",
      "requestWeather",
      "requestSystemInfo",
      "counterDraw",
      "statusDraw",
      "subscriptions",
      "view"
    ]

    results =
      Enum.map(names, fn name ->
        decl = Map.fetch!(decl_map, {"Main", name})

        case Elmc.Backend.Plan.Lower.Function.lower(decl, "Main", decl_map,
               rc_required: name not in ["counterOf", "view"]
             ) do
          {:ok, _} -> {:ok, name}
          other -> {other, name}
        end
      end)

    assert Enum.all?(results, &match?({:ok, _}, &1)),
           "expected all Main helpers to lower: #{inspect(results)}"
  end
end
