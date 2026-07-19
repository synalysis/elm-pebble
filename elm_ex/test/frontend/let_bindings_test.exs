defmodule ElmEx.Frontend.LetBindingsTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.{GeneratedExpressionParser, LetBindings, Pretty}

  test "parse preserves tuple and pattern bindings as let_bindings" do
    source = """
    let
        msg = update model
        ( _, paths ) = msg
    in
        paths
    """

    assert {:ok, %{op: :let_bindings, bindings: bindings}} = GeneratedExpressionParser.parse(source)
    assert length(bindings) == 2
    assert Enum.at(bindings, 1).kind == :pattern
  end

  test "expand matches legacy nested let_in lowering" do
    source = """
    let
        ( contents, fullExtent, wrappingExtent ) =
            case innerBound of
                Just x ->
                    1
                _ ->
                    0
    in
        contents
    """

    assert {:ok, ast} = GeneratedExpressionParser.parse(source)
    expanded = LetBindings.expand(ast)
    assert expanded.op == :let_in
    assert expanded.name == "__tupleBind_contents_fullExtent_wrappingExtent"
  end

  test "pretty prints let_bindings without synthetic names" do
    source = """
    let
        msg = update model
        ( _, paths ) = msg
    in
        paths
    """

    assert {:ok, ast} = GeneratedExpressionParser.parse(source)
    formatted = Pretty.format_expr(ast)

    assert formatted =~ "(_, paths) ="
    refute formatted =~ "__patternBind_"
    assert Pretty.round_trip?(source)
  end

  test "parse records inline_first layout when first binding follows let on same line" do
    source = """
    let a = 10
        b = a + 30
    in b
    """

    assert {:ok, %{op: :let_bindings, layout: :inline_first}} =
             GeneratedExpressionParser.parse(source)
  end

  test "pretty round-trips inline_first let layout" do
    source = """
    let a = 10
        b = a + 30
    in b
    """

    assert Pretty.round_trip?(source)
    assert Pretty.format_expr(elem(GeneratedExpressionParser.parse(source), 1)) =~ "let a = 10"
  end

  test "block let omits inline_first layout metadata" do
    source = """
    let
        a = 10
    in
        a
    """

    assert {:ok, ast} = GeneratedExpressionParser.parse(source)
    refute Map.get(ast, :layout) == :inline_first
  end
end
