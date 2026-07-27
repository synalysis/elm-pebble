defmodule ElmEx.Frontend.ExprLayoutLexerTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.ExprLayoutLexer
  alias ElmEx.Frontend.GeneratedExpressionParser
  alias ElmEx.Test.LetExprHelpers

  defp token_kind({kind, _, _}), do: kind
  defp token_kind({kind, _}), do: kind

  test "single-line source has no layout tokens" do
    assert {:ok, tokens, _} = ExprLayoutLexer.tokenize("1 + 2")
    assert Enum.all?(tokens, &(token_kind(&1) not in [:indent, :dedent, :newline]))
  end

  test "multiline let emits indent, newline, and dedent" do
    source = """
    let
        a = 1
    in
        a
    """

    assert {:ok, tokens, _} = ExprLayoutLexer.tokenize(source)
    kinds = Enum.map(tokens, &token_kind/1)

    assert :let_kw in kinds
    assert :indent in kinds
    assert :dedent in kinds
    assert :newline in kinds
    assert :in_kw in kinds
  end

  test "multiline case emits layout tokens around arms" do
    source = """
    case x of
        A ->
            1
        B ->
            2
    """

    assert {:ok, tokens, _} = ExprLayoutLexer.tokenize(source)
    kinds = Enum.map(tokens, &token_kind/1)

    assert :case_kw in kinds
    assert :of_kw in kinds
    assert :indent in kinds
    assert :newline in kinds
  end

  test "parse_with_layout_lexer parses multiline case" do
    source = """
    case x of
        A ->
            1
        B ->
            2
    """

    assert {:ok, %{op: :case, branches: branches}} =
             GeneratedExpressionParser.parse_with_layout_lexer(source)

    assert length(branches) == 2
  end

  test "parse_with_layout_lexer parses multiline let with split binding rhs" do
    source = """
    let
        counter =
            n + 1
    in
        counter + 2
    """

    assert {:ok, expr} =
             GeneratedExpressionParser.parse_with_layout_lexer(source)

    assert expr.op == :let_bindings
    assert LetExprHelpers.first_binding_name(expr) == "counter"
  end

  test "parse_with_layout_lexer parses sibling let bindings" do
    source = """
    let
        a = 1
        b = 2
    in
        a + b
    """

    assert {:ok, expr} =
             GeneratedExpressionParser.parse_with_layout_lexer(source)

    assert expr.op == :let_bindings
    assert LetExprHelpers.first_binding_name(expr) == "a"
  end

  test "parse_with_layout_lexer parses multiline if" do
    source = """
    if True then
        1
    else
        2
    """

    assert {:ok, %{op: :if}} = GeneratedExpressionParser.parse_with_layout_lexer(source)
  end

  test "parse_with_layout_lexer parses first binding on let line with siblings" do
    source = """
    let a = 10
        b = a + 30
    in b
    """

    assert {:ok, expr} =
             GeneratedExpressionParser.parse_with_layout_lexer(source)

    assert expr.op == :let_bindings
    assert expr.layout == :inline_first
    assert LetExprHelpers.first_binding_name(expr) == "a"
  end

  test "parse_with_layout_lexer parses pipe chain in let body" do
    source = """
    let
        a = 1
    in
        a
            |> f
    """

    assert {:ok, %{op: :let_bindings, in_expr: %{op: :pipe_chain}}} =
             GeneratedExpressionParser.parse_with_layout_lexer(source)
  end

  test "parse_with_layout_lexer parses nested let in case arm" do
    source = """
    case x of
        A ->
            let
                y = 1
            in
                y
    """

    assert {:ok, %{op: :case, branches: [%{expr: %{op: :let_bindings, bindings: [%{kind: :name, name: "y"} | _]}}]}} =
             GeneratedExpressionParser.parse_with_layout_lexer(source)
  end

  test "parse_with_layout_lexer parses leading plus before parenthesized case" do
    source = """
    phaseToInt x * 1000
    + (case w of
        Nothing -> 0
        Just n -> n)
    """

    assert {:ok, %{op: :call}} = GeneratedExpressionParser.parse_with_layout_lexer(source)
  end

  test "parse_with_layout_lexer parses if/case/else without extra dedent" do
    source = """
    if x then
        case args of
            [] ->
                Nothing
            _ ->
                Nothing
    else
        Nothing
    """

    assert {:ok, %{op: :if}} = GeneratedExpressionParser.parse_with_layout_lexer(source)
  end

  test "inline-first let tolerates deeper indented in keyword" do
    source = """
    let isolate = testState.isolate
        in
        isolate
    """

    assert {:ok, tokens, _} = ExprLayoutLexer.tokenize(source)
    kinds = Enum.map(tokens, &token_kind/1)
    refute Enum.any?(Enum.chunk_every(kinds, 2, 1, :discard), &(&1 == [:indent, :in_kw]))

    assert {:ok, %{op: :let_bindings}} =
             GeneratedExpressionParser.parse_with_layout_lexer(source)
  end
end
