defmodule Elmc.PlanConstantFoldTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.Lower.If, as: PlanIf
  alias Elmc.Backend.Plan.{Builder, ConstantFold, Context}

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

    project_dir = Path.expand("tmp/plan_fold_list_repeat", __DIR__)
    out_dir = Path.expand("tmp/plan_fold_list_repeat_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    refute generated_c =~ "140 <= 0"
    assert generated_c =~ "plan_list_int_values_"
    assert generated_c =~ "[140]"
    refute generated_c =~ "list_repeat_zero_buf_"
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

    project_dir = Path.expand("tmp/plan_fold_list_repeat_heritage", __DIR__)
    out_dir = Path.expand("tmp/plan_fold_list_repeat_heritage_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "plan_list_int_values_"
    assert generated_c =~ "[140]"

    empty_board =
      generated_c
      |> String.split("static RC elmc_fn_Main_emptyBoard")
      |> Enum.at(1, "")
      |> String.split("static ", parts: 2)
      |> hd()

    refute empty_board =~ "elmc_list_repeat"
    refute empty_board =~ "elmc_fn_Main_boardSize"
  end
end
