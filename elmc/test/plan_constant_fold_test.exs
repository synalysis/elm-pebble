defmodule Elmc.PlanConstantFoldTest do
  use Elmc.TestSupport.PrimaryCodegenCase, async: true

  alias Elmc.Backend.C.Lower.Function, as: CLowerFunction
  alias Elmc.Backend.CCodegen.IRQueries
  alias Elmc.Backend.Plan.Lower.Function, as: PlanLower
  alias Elmc.Backend.Plan.Lower.If, as: PlanIf
  alias Elmc.Backend.Plan.{Builder, ConstantFold, Context}
  alias Elmc.TestSupport.ElmJson
  alias ElmEx.Frontend.Bridge
  alias ElmEx.IR.Lowerer

  defp write_minimal_project!(project_dir, source) do
    ElmJson.write_probe_project!(project_dir, source)
  end

  defp lower_main!(source, fun_name) do
    project_dir = Path.expand("tmp/plan_fold_#{fun_name}", __DIR__)
    write_minimal_project!(project_dir, source)
    {:ok, project} = Bridge.load_project(project_dir)
    {:ok, ir} = Lowerer.lower_project(project)
    decl_map = IRQueries.function_decl_map(ir)

    case Map.get(decl_map, {"Main", fun_name}) do
      nil -> flunk("Main.#{fun_name} not found in lowered IR")
      decl -> {decl, decl_map}
    end
  end

  defp emit_main_c!(source, fun_name, opts \\ []) do
    {decl, decl_map} = lower_main!(source, fun_name)

    assert {:ok, plan} =
             PlanLower.lower(
               decl,
               "Main",
               decl_map,
               Keyword.merge([rc_required: true], opts)
             )

    CLowerFunction.emit(plan)
  end

  test "constant fold evaluates literal comparisons" do
    ctx = Context.new(module: "Main")

    assert ConstantFold.bool_value(
             %{
               op: :compare,
               kind: :lte,
               left: %{op: :int_literal, value: 140},
               right: %{op: :int_literal, value: 0}
             },
             ctx
           ) == false
  end

  test "plan if folds literal false comparison and skips CFG" do
    ctx =
      Context.new(
        module: "Main",
        function_name: "probe",
        rc_required: true,
        fallible: true
      )

    b = Builder.new("Main", "probe", rc_required: true, fallible: true)

    expr = %{
      op: :if,
      cond: %{
        op: :compare,
        kind: :lte,
        left: %{op: :int_literal, value: 140},
        right: %{op: :int_literal, value: 0}
      },
      then_expr: %{op: :int_literal, value: 1},
      else_expr: %{op: :int_literal, value: 2}
    }

    assert {:ok, _reg, b_out} = PlanIf.compile(expr, ctx, b)
    plan = Builder.to_function_plan(b_out)

    refute Enum.any?(plan.blocks, fn block ->
             match?({:br_if, _, _, _}, block.terminator)
           end)

    assert length(plan.blocks) == 1
  end

  test "legacy List.repeat with constant count does not emit dead non-positive branch" do
    source = """
    module Main exposing (board, len)

    board : List Int
    board =
        List.repeat 140 0

    len : Int
    len =
        List.length board
    """

    c = emit_main_c!(source, "board")

    refute c =~ "140 <= 0"
    assert c =~ "plan_list_int_values_"
    assert c =~ "[140]"
    refute c =~ "list_repeat_zero_buf_"
  end

  test "List.repeat with folded top-level count propagates into static int list" do
    source = """
    module Main exposing (boardCols, boardRows, boardSize, emptyBoard)

    boardCols : Int
    boardCols =
        10

    boardRows : Int
    boardRows =
        14

    boardSize : Int
    boardSize =
        boardCols * boardRows

    emptyBoard : List Int
    emptyBoard =
        List.repeat boardSize 0
    """

    c = emit_main_c!(source, "emptyBoard")

    assert c =~ "plan_list_int_values_"
    assert c =~ "[140]"
    refute c =~ "elmc_list_repeat"
    refute c =~ "elmc_fn_Main_boardSize"
  end
end
