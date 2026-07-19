defmodule ElmEx.Frontend.ApplyLeftTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.{ApplyLeft, GeneratedExpressionParser, Pretty}

  test "parse preserves apply_left instead of flattening into call args" do
    assert {:ok, %{op: :apply_left, fn_expr: %{target: "Svg.g"}, arg: arg}} =
             GeneratedExpressionParser.parse("Svg.g [] <| x")

    assert arg == %{op: :var, name: "x"}
  end

  test "expand matches legacy build_app lowering" do
    source = "f <| g"
    assert {:ok, ast} = GeneratedExpressionParser.parse(source)
    expanded = ApplyLeft.expand(ast)
    assert expanded == %{op: :call, name: "f", args: [%{op: :var, name: "g"}]}
  end

  test "pretty prints multiline apply_left with nested cons" do
    source = """
    Svg.g [] <|
        Svg.rect attrs []
            :: tail
    """

    assert {:ok, ast} = GeneratedExpressionParser.parse(source)
    formatted = Pretty.format_expr(ast)

    assert formatted =~ "<|"
    assert formatted =~ "Svg.g"
    assert formatted =~ "Svg.rect"
    assert formatted =~ ":: tail"
    refute formatted =~ "List.cons"
    assert Pretty.round_trip?(source)
  end
end
