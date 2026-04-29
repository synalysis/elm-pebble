defmodule Elmc.GoldenSnapshotTest do
  use ExUnit.Case

  alias ElmEx.Frontend.Bridge
  alias ElmEx.IR.Lowerer

  test "frontend to ir snapshots include known lowering patterns" do
    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    {:ok, project} = Bridge.load_project(project_dir)
    {:ok, ir} = Lowerer.lower_project(project)

    main = Enum.find(project.modules, &(&1.name == "Main"))
    assert main

    assert Enum.any?(
             main.declarations,
             &(&1.kind == :function_definition and &1.name == "headOrZero")
           )

    compliance_ir =
      ir.modules
      |> Enum.find(&(&1.name == "CoreCompliance"))
      |> Map.fetch!(:declarations)

    fold_sum = Enum.find(compliance_ir, &(&1.name == "foldSum"))
    maybe_inc = Enum.find(compliance_ir, &(&1.name == "maybeInc"))
    char_from_code = Enum.find(compliance_ir, &(&1.name == "charFromCode"))
    tuple_case = Enum.find(compliance_ir, &(&1.name == "tupleCase"))
    nested_result = Enum.find(compliance_ir, &(&1.name == "nestedResult"))
    result_inc = Enum.find(compliance_ir, &(&1.name == "resultInc"))
    first = Enum.find(compliance_ir, &(&1.name == "first"))
    nested_tuple_sum = Enum.find(compliance_ir, &(&1.name == "nestedTupleSum"))
    branch_tuple_out = Enum.find(compliance_ir, &(&1.name == "branchTupleOut"))
    branch_tuple_out_nested = Enum.find(compliance_ir, &(&1.name == "branchTupleOutNested"))

    assert fold_sum.expr.op == :qualified_call
    assert fold_sum.expr.target == "List.foldl"
    assert maybe_inc.expr.op == :qualified_call
    assert maybe_inc.expr.target == "Maybe.withDefault"
    assert char_from_code.expr.op in [:char_from_code, :char_from_code_expr]
    assert tuple_case.expr.op == :case
    assert nested_result.expr.op == :case
    assert result_inc.expr.op == :case
    assert first.expr.op in [:tuple_first, :tuple_first_expr]
    assert nested_tuple_sum.expr.op == :case

    ui_ir =
      ir.modules
      |> Enum.find(&(&1.name == "Pebble.Ui"))
      |> Map.fetch!(:declarations)

    text_int_expr = Enum.find(ui_ir, &(&1.name == "textInt")).expr
    assert text_int_expr.op == :tuple2
    assert text_int_expr.left.op == :int_literal

    main_ir =
      ir.modules
      |> Enum.find(&(&1.name == "Main"))
      |> Map.fetch!(:declarations)

    assert Enum.find(main_ir, &(&1.name == "view")).expr.op == :qualified_call
    assert Enum.find(main_ir, &(&1.name == "advanced")).expr.op == :let_in
    assert branch_tuple_out.expr.op == :case
    assert branch_tuple_out_nested.expr.op == :case
  end

  test "generated c contains concrete helper calls for lowered expressions" do
    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    out_dir = Path.expand("tmp/snapshots", __DIR__)
    File.rm_rf!(out_dir)
    {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, strip_dead_code: false})

    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert String.contains?(generated, "elmc_list_foldl")
    assert String.contains?(generated, "elmc_maybe_map")
    assert String.contains?(generated, "elmc_maybe_with_default")
    assert String.contains?(generated, "elmc_tuple_second")
    assert String.contains?(generated, "elmc_tuple_first")
    assert String.contains?(generated, "elmc_string_length")
    assert String.contains?(generated, "ELMC_TAG_RESULT")
    assert String.contains?(generated, "ELMC_TAG_TUPLE2")
    assert String.contains?(generated, "((ElmcTuple2 *)pair->payload)->first")

    assert String.contains?(
             generated,
             "((ElmcTuple2 *)((ElmcTuple2 *)value->payload)->first->payload)->first"
           )

    refute String.contains?(generated, "elmc_result_inc_or_zero")
    assert String.contains?(generated, "elmc_fn_CoreCompliance_branchTupleOut")
    assert String.contains?(generated, "elmc_fn_CoreCompliance_branchTupleOutNested")

    assert String.contains?(
             generated,
             "((ElmcResult *)((ElmcTuple2 *)value->payload)->first->payload)->value"
           )

    assert String.contains?(
             generated,
             "((ElmcMaybe *)((ElmcTuple2 *)pair->payload)->second->payload)->value"
           )

    assert String.contains?(generated, "elmc_as_int(msg) == 1")
  end
end
