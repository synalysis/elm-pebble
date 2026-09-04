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

  test "parse_with_layout_lexer parses case with multiline subject" do
    source = """
    case
        x
    of
        A ->
            1

        _ ->
            2
    """

    assert {:ok, %{op: :case, subject: "x", branches: branches}} =
             GeneratedExpressionParser.parse_with_layout_lexer(source)

    assert length(branches) == 2
  end

  test "parse_with_layout_lexer parses nested case under multiline subject" do
    source = """
    let
        ( templateModel, templateCmd ) =
            case
                subject
            of
                Nothing ->
                    0

                Just justRouteAndPath ->
                    case x of
                        A ->
                            1

                        _ ->
                            2
    in
        0
    """

    assert {:ok, %{op: :let_bindings}} =
             GeneratedExpressionParser.parse_with_layout_lexer(source)
  end

  test "parse_with_layout_lexer keeps multiline tuple after nested cases in let" do
    source = """
    let
        ( templateModel, templateCmd ) =
            case
                subject
            of
                Nothing ->
                    0

                Just x ->
                    case y of
                        A ->
                            1

                        _ ->
                            2
    in
        ( { global = sharedModel, page = templateModel }
        , Effect.batch [ templateCmd, other ]
        )
    """

    assert {:ok, %{op: :let_bindings, in_expr: %{op: :tuple2}}} =
             GeneratedExpressionParser.parse_with_layout_lexer(source)
  end

  test "parse_with_layout_lexer keeps case siblings after let-in inside an arm" do
    source = """
    case msg of
        MsgErrorPage msg_ ->
            let
                ( updatedPageModel, pageCmd ) =
                    case model.page of
                        ModelErrorPage pageModel ->
                            1

                        _ ->
                            2
            in
            ( { model | page = updatedPageModel }, pageCmd )

        MsgGlobal msg_ ->
            ( model, Cmd.none )
    """

    assert {:ok, %{op: :case, branches: branches}} =
             GeneratedExpressionParser.parse_with_layout_lexer(source)

    assert length(branches) == 2
  end

  test "parse strips block comments that contain apostrophes" do
    source = """
    case result of
        Err _ ->
            -- I think that's the right logic
            {-
               we're navigating to. This could be done more cleanly, but it's simplest.
            -}
            ( model, Cmd.none )

        Ok value ->
            ( value, Cmd.none )
    """

    assert {:ok, %{op: :case, branches: branches}} =
             GeneratedExpressionParser.parse(source)

    assert length(branches) == 2
  end

  test "parse_with_layout_lexer parses case inside list without trailing dedent" do
    source = """
    { title = "Greetings"
    , body =
        [ Html.div []
            [ case app.data.name of
                Just name ->
                    Html.text ("Hello " ++ name)

                Nothing ->
                    Html.text "hi"
            ]
        ]
    }
    """

    assert {:ok, %{op: :record_literal}} =
             GeneratedExpressionParser.parse_with_layout_lexer(source)
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

  test "nested case inside a parenthesized lambda keeps the outer wildcard" do
    source = """
    D.string
        |> D.andThen
            (\\s ->
                case String.split "." s of
                    [ a, b, c ] ->
                        case ( String.toInt a, String.toInt b, String.toInt c ) of
                            ( Just x, Just y, Just z ) ->
                                D.succeed ( x, y, z )

                            _ ->
                                D.fail "bad version"

                    _ ->
                        D.fail "bad version"
            )
    """

    assert {:ok, expr} = GeneratedExpressionParser.parse_with_layout_lexer(source)

    count_cases = fn count_cases, node, acc ->
      case node do
        %{op: :case, branches: branches} ->
          acc = [length(branches) | acc]
          Enum.reduce(branches, acc, fn br, acc -> count_cases.(count_cases, br.expr, acc) end)

        map when is_map(map) ->
          Enum.reduce(map, acc, fn {_k, v}, acc -> count_cases.(count_cases, v, acc) end)

        list when is_list(list) ->
          Enum.reduce(list, acc, fn v, acc -> count_cases.(count_cases, v, acc) end)

        _ ->
          acc
      end
    end

    assert Enum.sort(count_cases.(count_cases, expr, [])) == [2, 2]
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
