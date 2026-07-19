defmodule ElmEx.Test.Frontend.BoolOpsTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.{BoolOps, GeneratedExpressionParser, Pretty}

  test "parse preserves bool_and instead of nested if desugar" do
    assert {:ok, %{op: :bool_and, left: left, right: right}} =
             GeneratedExpressionParser.parse("crossed && not previousAbove && above")

    assert %{op: :var, name: "crossed"} = left
    assert %{op: :bool_and} = right
  end

  test "parse preserves bool_or instead of nested if desugar" do
    assert {:ok, %{op: :bool_or, left: left, right: right}} =
             GeneratedExpressionParser.parse("a || b || c")

    assert %{op: :var, name: "a"} = left
    assert %{op: :bool_or} = right
  end

  test "expand lowers bool_and to legacy if shape" do
    {:ok, ast} = GeneratedExpressionParser.parse("crossed && above")

    assert %{
             op: :if,
             cond: %{op: :var, name: "crossed"},
             then_expr: %{op: :var, name: "above"},
             else_expr: %{op: :constructor_ref, target: "False"}
           } = BoolOps.expand(ast)
  end

  test "pretty prints && round trip for nested condition in let binding" do
    source =
      "if crossed && not previousAbove && above && scan.rise == Nothing then Just 1 else scan.rise"

    assert {:ok, ast} = GeneratedExpressionParser.parse(source)
    formatted = Pretty.format_expr(ast)
    assert formatted =~ "&&"
    refute formatted =~ "if if"

    assert {:ok, _} = GeneratedExpressionParser.parse(formatted)
  end
end
