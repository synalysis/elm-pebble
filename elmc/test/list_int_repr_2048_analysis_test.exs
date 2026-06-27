defmodule Elmc.ListIntRepr2048AnalysisTest do
  use ExUnit.Case, async: true

  @template_main Path.expand("../../ide/priv/project_templates/game_2048/src/Main.elm", __DIR__)

  test "2048 countEmpty and spawnTileWithSeed cells params analyze as int_list" do
    project_dir = Path.expand("tmp/list_int_repr_2048_analysis", __DIR__)

    File.mkdir_p!(Path.join(project_dir, "src"))
    File.cp!(Path.expand("fixtures/simple_project/elm.json", __DIR__), Path.join(project_dir, "elm.json"))
    File.write!(Path.join(project_dir, "src/Main.elm"), File.read!(@template_main))

    assert {:ok, result} =
             Elmc.compile(project_dir, %{
               out_dir: Path.expand("tmp/list_int_repr_2048_analysis_out", __DIR__),
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
    assert Map.get(plans.param_plans, {"Main", "countEmpty", "cells"}).layout == :compact
  end

  test "2048 countEmpty emits int-list-only loop in generated C" do
    project_dir = Path.expand("tmp/list_int_repr_2048_codegen", __DIR__)
    out_dir = Path.expand("tmp/list_int_repr_2048_codegen_out", __DIR__)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.cp!(Path.expand("fixtures/simple_project/elm.json", __DIR__), Path.join(project_dir, "elm.json"))
    File.write!(Path.join(project_dir, "src/Main.elm"), File.read!(@template_main))

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    count_empty_native =
      generated_c
      |> String.split("static elmc_int_t elmc_fn_Main_countEmpty_native(ElmcValue * const cells) {", parts: 2)
      |> Enum.at(1, "")
      |> String.split("\n}\n", parts: 2)
      |> List.first()

    assert count_empty_native =~ "ELMC_TAG_INT_LIST"
    refute count_empty_native =~ "list_walk_cursor_"
  end
end
