defmodule Elmc.StoragePlanOptimizationGateTest do
  @moduledoc """
  CI gate for StoragePlan / RAM optimizations on the 2048 template and record-grid fixture.
  """
  use ExUnit.Case, async: false

  alias Elmc.TestSupport.CachedCompile
  alias Elmc.Test.{CCodegenExtract, FixtureCodegen}

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
             CachedCompile.compile(project_dir, %{
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

    initial_board_body = CCodegenExtract.fn_body(generated, "elmc_fn_Main_initialBoard")
    spawn_tile_body = CCodegenExtract.fn_body(generated, "elmc_fn_Main_spawnTileWithSeed")

    assert initial_board_body =~ "plan block"
    assert initial_board_body =~ "elmc_fn_Main_spawnTileWithSeed"
    assert spawn_tile_body =~ "plan block"
    assert spawn_tile_body =~ "elmc_fn_Main_countEmpty"
    refute generated =~ "elmc_fn_Main_spawnTileWithSeed(&tmp_"

    count_empty_body = CCodegenExtract.fn_body(generated, "elmc_fn_Main_countEmpty")
    assert count_empty_body =~ "plan block"
    assert count_empty_body =~ "elmc_list_head_with_default_int"
    assert count_empty_body =~ "elmc_int_list_tail"
    refute count_empty_body =~ "list_walk_cursor_"

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
             CachedCompile.compile(FixtureCodegen.project_dir("storage_plan_record_grid_project"), %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true
             })

    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated =~ "elmc_fn_Main_sumRows"

    sum_rows_body = CCodegenExtract.fn_body(generated, "elmc_fn_Main_sumRows")

    assert sum_rows_body =~ "plan block"
    assert sum_rows_body =~ "ELMC_RECORD_GET_INDEX_INT"
    assert sum_rows_body =~ "elmc_list_head" or sum_rows_body =~ "elmc_list_is_empty"
  end
end
