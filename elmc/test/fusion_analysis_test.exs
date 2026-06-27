defmodule Elmc.FusionAnalysisTest do
  use ExUnit.Case, async: true

  @template_main Path.expand("../../ide/priv/project_templates/game_2048/src/Main.elm", __DIR__)

  test "permute merge fusion resolves model field macros from record field types alone" do
    project_dir = Path.expand("tmp/fusion_analysis_field_macros", __DIR__)

    File.mkdir_p!(Path.join(project_dir, "src"))
    File.cp!(Path.expand("fixtures/simple_project/elm.json", __DIR__), Path.join(project_dir, "elm.json"))
    File.write!(Path.join(project_dir, "src/Main.elm"), File.read!(@template_main))

    assert {:ok, result} =
             Elmc.compile(project_dir, %{
               out_dir: Path.expand("tmp/fusion_analysis_field_macros_out", __DIR__),
               entry_module: "Main",
               strip_dead_code: true
             })

    decl_map = Elmc.Backend.CCodegen.IRQueries.function_decl_map(result.ir)

    Process.put(
      :elmc_record_field_types,
      Elmc.Backend.CCodegen.IRQueries.record_alias_field_types_map(result.ir)
    )

    decl = Map.get(decl_map, {"Main", "moveBoard"})

    assert match?({:ok, _, _, :rc_native},
             Elmc.Backend.CCodegen.PermuteMergeInversePipeline.try_emit(
               "Main",
               "moveBoard",
               decl.expr,
               decl_map
             ))
  end

  test "fused callers are excluded from spawnTileWithSeed cells repr sites" do
    project_dir = Path.expand("tmp/fusion_analysis_spawn_sites", __DIR__)

    File.mkdir_p!(Path.join(project_dir, "src"))
    File.cp!(Path.expand("fixtures/simple_project/elm.json", __DIR__), Path.join(project_dir, "elm.json"))
    File.write!(Path.join(project_dir, "src/Main.elm"), File.read!(@template_main))

    assert {:ok, result} =
             Elmc.compile(project_dir, %{
               out_dir: Path.expand("tmp/fusion_analysis_spawn_sites_out", __DIR__),
               entry_module: "Main",
               strip_dead_code: true
             })

    decl_map = Elmc.Backend.CCodegen.IRQueries.function_decl_map(result.ir)

    Process.put(
      :elmc_record_field_types,
      Elmc.Backend.CCodegen.IRQueries.record_alias_field_types_map(result.ir)
    )

    plans = Elmc.Backend.CCodegen.LayoutSolver.analyze(decl_map)

    assert Map.get(plans.param_plans, {"Main", "spawnTileWithSeed", "cells"}).layout == :compact
    assert Map.get(plans.param_plans, {"Main", "setCell", "cells"}).layout == :compact
  end
end
