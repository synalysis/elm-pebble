defmodule Elmc.ListIntReprCodegenTest do
  use ExUnit.Case, async: true

  alias Elmc.TestSupport.CachedCompile
  alias Elmc.Backend.CCodegen.{LayoutSolver, SchemaRegistry, StoragePlan}
  alias Elmc.Test.CCodegenExtract

  defp compile_main!(source, project_name) do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/#{project_name}", __DIR__)
    out_dir = Path.expand("tmp/#{project_name}_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_fixture, project_dir)

    File.write!(Path.join(project_dir, "src/Main.elm"), source)

    assert {:ok, result} =
             CachedCompile.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true
             })

    {File.read!(Path.join(out_dir, "c/elmc_generated.c")), result}
  end

  test "countEmpty emits plan int-list loop when all callers pass compact lists" do
    {generated_c, _result} =
      compile_main!(
        """
        module Main exposing (main)

        emptyBoard : List Int
        emptyBoard =
            List.repeat 16 0

        countEmpty : List Int -> Int
        countEmpty cells =
            case cells of
                [] ->
                    0

                value :: rest ->
                    (if value == 0 then
                        1

                     else
                        0
                    )
                        + countEmpty rest

        useCount : List Int -> Int
        useCount cells =
            countEmpty cells

        main =
            useCount emptyBoard
        """,
        "list_int_repr_compact_only"
      )

    count_empty_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_countEmpty")

    assert count_empty_body =~ "plan block"
    assert count_empty_body =~ "elmc_list_head_with_default_int"
    assert count_empty_body =~ "elmc_int_list_tail"
    refute count_empty_body =~ "list_walk_cursor_"
    refute count_empty_body =~ "list_walk_node_"
  end

  test "caller passing [] keeps dual-path layout for countEmpty cells param" do
    {generated_c, result} =
      compile_main!(
        """
        module Main exposing (main)

        countEmpty : List Int -> Int
        countEmpty cells =
            case cells of
                [] ->
                    0

                value :: rest ->
                    (if value == 0 then
                        1

                     else
                        0
                    )
                        + countEmpty rest

        main =
            countEmpty []
        """,
        "list_int_repr_dual_path"
      )

    decl_map = Elmc.Backend.CCodegen.IRQueries.function_decl_map(result.ir)

    Process.put(
      :elmc_record_field_types,
      Elmc.Backend.CCodegen.IRQueries.record_alias_field_types_map(result.ir)
    )

    registry = SchemaRegistry.build(result.ir)
    plans = LayoutSolver.analyze(decl_map, registry)

    plan = Map.get(plans.param_plans, {"Main", "countEmpty", "cells"})
    assert StoragePlan.dual_path?(plan)

    count_empty_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_countEmpty")

    assert count_empty_body =~ "plan block"
    assert count_empty_body =~ "elmc_list_is_empty"
    assert count_empty_body =~ "elmc_list_head_with_default_int"
    refute count_empty_body =~ "RC_ERR_UNSUPPORTED"
    refute count_empty_body =~ "list_walk_cursor_"
  end
end
