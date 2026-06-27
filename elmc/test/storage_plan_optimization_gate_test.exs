defmodule Elmc.StoragePlanOptimizationGateTest do
  @moduledoc """
  CI gate for StoragePlan / RAM optimizations on the 2048 template and record-grid fixture.
  """
  use ExUnit.Case, async: false

  alias Elmc.Test.FixtureCodegen

  @template_main Path.expand("../../ide/priv/project_templates/game_2048/src/Main.elm", __DIR__)

  @tag :fixture_codegen
  @tag :storage_plan
  test "2048 template keeps compact int-list analysis and codegen" do
    project_dir = Path.expand("tmp/storage_plan_gate_2048", __DIR__)
    out_dir = Path.expand("tmp/storage_plan_gate_2048_out", __DIR__)

    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.cp!(Path.expand("fixtures/simple_project/elm.json", __DIR__), Path.join(project_dir, "elm.json"))
    File.write!(Path.join(project_dir, "src/Main.elm"), File.read!(@template_main))

    assert {:ok, result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true,
               prune_runtime: true
             })

    decl_map = Elmc.Backend.CCodegen.IRQueries.function_decl_map(result.ir)

    Process.put(
      :elmc_record_field_types,
      Elmc.Backend.CCodegen.IRQueries.record_alias_field_types_map(result.ir)
    )

    plans = Elmc.Backend.CCodegen.LayoutSolver.analyze(decl_map)

    assert Map.get(plans.param_plans, {"Main", "spawnTileWithSeed", "cells"}).layout == :compact
    assert Map.get(plans.param_plans, {"Main", "countEmpty", "cells"}).layout == :compact

    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    runtime = File.read!(Path.join(out_dir, "runtime/elmc_runtime.c"))

    assert generated =~ "static RC elmc_fn_Main_initialBoard_native("
    assert generated =~ "spawn_a_after_tile"
    assert generated =~ "spawn_b_after_tile"
    refute generated =~ "elmc_fn_Main_spawnTileWithSeed(&tmp_"

    count_empty =
      generated
      |> String.split("static elmc_int_t elmc_fn_Main_countEmpty_native(ElmcValue * const cells) {", parts: 2)
      |> Enum.at(1, "")
      |> String.split("\n}\n", parts: 2)
      |> List.first()

    assert count_empty =~ "ELMC_TAG_INT_LIST"
    refute count_empty =~ "list_walk_cursor_"

    refute runtime =~ "elmc_float_list_alloc_copy"
    refute runtime =~ "elmc_record_seq_alloc_copy"
    refute runtime =~ "elmc_int_spine_head_native"
  end

  @tag :fixture_codegen
  @tag :storage_plan
  test "record grid fixture compiles with compact record-seq lowering" do
    out_dir = Path.join(System.tmp_dir!(), "storage_plan_gate_record_grid")
    File.rm_rf!(out_dir)

    assert {:ok, _} =
             Elmc.compile(FixtureCodegen.project_dir("storage_plan_record_grid_project"), %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true
             })

    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated =~ "elmc_fn_Main_sumRows"

    sum_rows_body =
      generated
      |> String.split("static ElmcValue * elmc_fn_Main_sumRows(ElmcValue ** const args, const int argc) {", parts: 2)
      |> Enum.at(1, "")
      |> String.split("\n}\n", parts: 2)
      |> List.first()

    assert sum_rows_body =~ "ELMC_TAG_RECORD_SEQ"
  end
end
