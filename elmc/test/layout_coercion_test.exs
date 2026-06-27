defmodule Elmc.LayoutCoercionTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.LayoutCoerceEmit
  alias Elmc.Backend.CCodegen.LayoutSolver
  alias Elmc.Backend.CCodegen.StoragePlan

  defp compile_decl_map!(source, project_name) do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/#{project_name}", __DIR__)
    out_dir = Path.expand("tmp/#{project_name}_out", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), source)

    assert {:ok, result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true
             })

    {result, Elmc.Backend.CCodegen.IRQueries.function_decl_map(result.ir)}
  end

  test "compact to dual-path callee emits layout_coercion_required warning" do
    source = """
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

    alsoCount : Int
    alsoCount =
        countEmpty []

    useCount : List Int -> Int
    useCount board =
        countEmpty board

    main =
        useCount emptyBoard + alsoCount
    """

    {result, _decl_map} = compile_decl_map!(source, "layout_coercion_compact_to_dual")

    assert Enum.any?(result.layout_coercion_diagnostics, fn warning ->
             warning["code"] == "layout_coercion_required" and
               warning["function"] == "useCount" and warning["param"] == "cells" and
               warning["from"] == "compact" and warning["to"] == "mixed"
           end)
  end

  test "compact to compact call produces no layout coercion warnings" do
    source = """
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

    main =
        countEmpty emptyBoard
    """

    {result, _decl_map} = compile_decl_map!(source, "layout_coercion_compact_ok")

    refute Enum.any?(result.layout_coercion_diagnostics, &(&1["code"] == "layout_coercion_required"))
  end

  test "collect_call_warnings finds compact to dual-path mismatch at analysis time" do
    source = """
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

    alsoCount : Int
    alsoCount =
        countEmpty []

    useCount : List Int -> Int
    useCount board =
        countEmpty board

    main =
        useCount emptyBoard + alsoCount
    """

    {_result, decl_map} = compile_decl_map!(source, "layout_coercion_analysis")

    Process.put(:elmc_record_field_types, %{})

    plans = LayoutSolver.analyze(decl_map)
    Process.put(:elmc_storage_plans, plans)

    warnings = LayoutCoerceEmit.collect_call_warnings(decl_map, plans.param_plans)

    assert Enum.any?(warnings, fn warning ->
             warning.code == "layout_coercion_required" and warning.function == "useCount"
           end)
  end

  test "diagnostic helper reports compact to native_linked" do
    from = StoragePlan.int_compact()
    to = StoragePlan.int_native_linked()

    assert %{
             source: "elmc/layout",
             code: "layout_coercion_required",
             from: :compact,
             to: :native_linked
           } = LayoutCoerceEmit.diagnostic(from, to)
  end

  test "diagnostic helper reports compact to dual-path mixed" do
    from = StoragePlan.int_compact()
    to = StoragePlan.mixed()

    assert %{
             source: "elmc/layout",
             code: "layout_coercion_required",
             from: :compact,
             to: :mixed
           } = LayoutCoerceEmit.diagnostic(from, to)
  end

  test "emit_layout_copy generates spine coercion for compact to native_linked" do
    {code, var, _next, true} =
      LayoutCoerceEmit.emit_layout_copy(
        "board",
        StoragePlan.int_compact(),
        StoragePlan.int_native_linked(),
        7
      )

    assert var == "layout_coerced_7"
    assert code =~ "elmc_int_list_to_spine"
    assert code =~ "ELMC_TAG_INT_LIST"
  end

  test "emit_layout_copy generates cons coercion for compact to boxed_cons" do
    {code, var, _next, true} =
      LayoutCoerceEmit.emit_layout_copy(
        "cells",
        StoragePlan.int_compact(),
        %StoragePlan{elem: {:primitive, :int}, layout: :boxed_cons, length: :unknown, access: :sequential},
        3
      )

    assert var == "layout_coerced_3"
    assert code =~ "elmc_int_list_to_cons"
  end

  test "emit_layout_copy skips compact to mixed mismatch" do
    assert {"", "board", 1, false} =
             LayoutCoerceEmit.emit_layout_copy(
               "board",
               StoragePlan.int_compact(),
               StoragePlan.mixed(),
               1
             )
  end

  test "compact to mixed call emits no layout copy in generated C" do
    source = """
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

    alsoCount : Int
    alsoCount =
        countEmpty []

    useCount : List Int -> Int
    useCount board =
        countEmpty board

    main =
        useCount emptyBoard + alsoCount
    """

    {result, _decl_map} = compile_decl_map!(source, "layout_coercion_no_copy")

    generated =
      File.read!(Path.join(Path.expand("tmp/layout_coercion_no_copy_out", __DIR__), "c/elmc_generated.c"))

    refute generated =~ "elmc_int_list_to_spine"
    refute generated =~ "layout_coerced_"
    assert Enum.any?(result.layout_coercion_diagnostics, &(&1["code"] == "layout_coercion_required"))
  end
end
