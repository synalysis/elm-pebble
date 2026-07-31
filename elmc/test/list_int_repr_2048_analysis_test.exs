defmodule Elmc.ListIntRepr2048AnalysisTest do
  use ExUnit.Case, async: true

  alias Elmc.TestSupport.CachedCompile
  alias Elmc.Test.CCodegenExtract

  @moduletag timeout: 360_000

  @template_main Path.expand("../../ide/priv/project_templates/game_2048/src/Main.elm", __DIR__)

  test "2048 countEmpty and spawnTileWithSeed cells params analyze as int_list" do
    project_dir = Path.expand("tmp/list_int_repr_2048_analysis", __DIR__)

    File.mkdir_p!(Path.join(project_dir, "src"))
    File.cp!(Path.expand("fixtures/simple_project/elm.json", __DIR__), Path.join(project_dir, "elm.json"))
    File.write!(Path.join(project_dir, "src/Main.elm"), File.read!(@template_main))

    assert {:ok, result} =
             CachedCompile.compile(project_dir, %{
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
             CachedCompile.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false,
               plan_ir_mode: :primary
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    count_empty_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_countEmpty")

    assert count_empty_body != ""
    assert count_empty_body =~ "elmc_int_list_tail"
    assert count_empty_body =~ "elmc_list_head_with_default_int"
  end
end
