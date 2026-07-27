defmodule Elmc.StoragePlanSolverTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.LayoutCoerceEmit
  alias Elmc.Backend.CCodegen.LayoutSolver
  alias Elmc.Backend.CCodegen.LayoutTransfer
  alias Elmc.Backend.CCodegen.SchemaRegistry
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

    decl_map = Elmc.Backend.CCodegen.IRQueries.function_decl_map(result.ir)

    Process.put(
      :elmc_record_field_types,
      Elmc.Backend.CCodegen.IRQueries.record_alias_field_types_map(result.ir)
    )

    registry = SchemaRegistry.build(result.ir)
    Process.put(:elmc_schema_registry, registry)

    plans = LayoutSolver.analyze(decl_map, registry)
    Process.put(:elmc_storage_plans, plans)

    {decl_map, plans, registry}
  end

  test "List.repeat 16 0 param analyzes as compact int" do
    source = """
    module Main exposing (main)

    emptyBoard : List Int
    emptyBoard =
        List.repeat 16 0

    useBoard : List Int -> Int
    useBoard cells =
        List.length cells

    main =
        useBoard emptyBoard
    """

    {_decl_map, plans, _registry} = compile_decl_map!(source, "storage_plan_repeat")

    assert Map.get(plans.param_plans, {"Main", "useBoard", "cells"}) ==
             StoragePlan.int_compact()
  end

  test "countEmpty with compact callers analyzes as compact int" do
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

    useCount : List Int -> Int
    useCount cells =
        countEmpty cells

    main =
        useCount emptyBoard
    """

    {_decl_map, plans, _registry} = compile_decl_map!(source, "storage_plan_count_empty")

    plan = Map.get(plans.param_plans, {"Main", "countEmpty", "cells"})
    assert StoragePlan.compact_only?(plan)
  end

  test "caller passing [] keeps dual-path plan for countEmpty" do
    source = """
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
    """

    {_decl_map, plans, _registry} = compile_decl_map!(source, "storage_plan_dual")

    plan = Map.get(plans.param_plans, {"Main", "countEmpty", "cells"})
    assert StoragePlan.dual_path?(plan)
  end

  test "LayoutTransfer: List.filter widens compact int to native linked" do
    plan =
      LayoutTransfer.output_plan(
        "List.filter",
        [%{op: :var, name: "pred"}, %{op: :var, name: "list"}],
        StoragePlan.int_compact(),
        elem_schema: {:primitive, :int}
      )

    assert plan.layout == :native_linked
    assert plan.elem == {:primitive, :int}
  end

  test "LayoutTransfer: List.repeat with known length stays compact" do
    plan =
      LayoutTransfer.output_plan(
        "List.repeat",
        [%{op: :int_literal, value: 16}, %{op: :int_literal, value: 0}],
        nil,
        elem_schema: {:primitive, :int}
      )

    assert StoragePlan.compact_only?(plan)
    assert plan.length == :known
  end

  test "LayoutTransfer: Array.fromList preserves compact input" do
    plan =
      LayoutTransfer.output_plan(
        "Array.fromList",
        [%{op: :var, name: "xs"}],
        StoragePlan.int_compact(length: :known),
        elem_schema: {:primitive, :int}
      )

    assert StoragePlan.compact_only?(plan)
    assert plan.access == :random
  end

  test "LayoutTransfer: union element list stays mixed" do
    plan =
      LayoutTransfer.output_plan(
        "List.repeat",
        [%{op: :int_literal, value: 4}, %{op: :var, name: "x"}],
        nil,
        elem_schema: {:boxed, :value}
      )

    assert plan.layout == :mixed
  end

  test "LayoutCoerceEmit reports layout_coercion_required diagnostic" do
    from = StoragePlan.int_compact()
    to = StoragePlan.int_native_linked()

    assert %{
             source: "elmc/layout",
             code: "layout_coercion_required",
             from: :compact,
             to: :native_linked
           } = LayoutCoerceEmit.diagnostic(from, to)

    {_var, _plan, diag} = LayoutCoerceEmit.maybe_coerce_expr("cells", from, to)
    assert diag.code == "layout_coercion_required"
  end

  test "LayoutTransfer: float repeat with known length stays compact" do
    plan =
      LayoutTransfer.output_plan(
        "List.repeat",
        [%{op: :int_literal, value: 4}, %{op: :float_literal, value: 1.5}],
        nil,
        elem_schema: {:primitive, :float}
      )

    assert StoragePlan.compact_only?(plan)
    assert plan.elem == {:primitive, :float}
  end

  test "List.repeat float param analyzes as compact float list" do
    source = """
    module Main exposing (main)

    weights : List Float
    weights =
        List.repeat 4 1.5

    sumWeights : List Float -> Float
    sumWeights xs =
        case xs of
            [] ->
                0

            x :: rest ->
                x + sumWeights rest

    main =
        sumWeights weights
    """

    {_decl_map, plans, _registry} = compile_decl_map!(source, "storage_plan_float_repeat")
    plan = Map.get(plans.param_plans, {"Main", "sumWeights", "xs"})
    assert plan.layout == :compact
    assert plan.elem == {:primitive, :float}
  end

  test "record grid sumRows param can analyze as compact record seq" do
    fixture = Path.expand("fixtures/storage_plan_record_grid_project", __DIR__)
    project_dir = Path.expand("tmp/storage_plan_record_solver", __DIR__)
    out_dir = Path.expand("tmp/storage_plan_record_solver_out", __DIR__)
    File.rm_rf!(project_dir)
    File.cp_r!(fixture, project_dir)

    assert {:ok, result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true
             })

    decl_map = Elmc.Backend.CCodegen.IRQueries.function_decl_map(result.ir)
    registry = SchemaRegistry.build(result.ir)
    Process.put(:elmc_record_field_types, Elmc.Backend.CCodegen.IRQueries.record_alias_field_types_map(result.ir))
    plans = LayoutSolver.analyze(decl_map, registry)

    plan = Map.get(plans.param_plans, {"Main", "sumRows", "cells"})
    assert plan.layout == :compact
    assert plan.elem == {:record, "Main", "Cell"}
  end

  test "mixed record list params analyze as boxed cons not dual int-list" do
    assert StoragePlan.from_record_repr(:mixed, {"Main", "Point"}) ==
             %StoragePlan{
               elem: {:record, "Main", "Point"},
               layout: :boxed_cons,
               length: :unknown,
               access: :sequential
             }

    assert LayoutSolver.codegen_loop_repr(StoragePlan.from_record_repr(:mixed, {"Main", "Point"})) ==
             :cons

    refute StoragePlan.int_list_dual_eligible?(StoragePlan.from_record_repr(:mixed, {"Main", "Point"}))
  end

  test "binding plans mark native int lets" do
    source = """
    module Main exposing (main)

    step : Int
    step =
        let
            doubled = 3 * 2
        in
        doubled + 1

    main =
        step
    """

    {_decl_map, plans, _registry} = compile_decl_map!(source, "storage_plan_bindings")
    assert Map.get(plans.binding_plans, {"Main", "step", "doubled"}) == StoragePlan.scalar_unboxed(:int)
  end
end
