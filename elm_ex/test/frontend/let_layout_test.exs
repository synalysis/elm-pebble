defmodule ElmEx.Frontend.LetLayoutTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.GeneratedExpressionParser
  alias ElmEx.Frontend.GeneratedParser
  alias ElmEx.Frontend.LetLayout

  test "validate rejects let and in on the same line" do
    assert {:error, {:inline_let_in, 1}} =
             LetLayout.validate("let counter = n + 1 in counter + 2")
  end

  test "validate accepts multiline let/in layout" do
    source = """
    let
        counter =
            n + 1
    in
    counter + 2
    """

    assert :ok = LetLayout.validate(source)
    assert {:ok, expr} = GeneratedExpressionParser.parse(source)
    assert expr.op == :let_in
  end

  test "parses multiline let with first binding on let line and additional bindings" do
    source = """
    let a = 10 + 20
        b = a + 30
        c = b * 2
    in c
    """

    assert {:ok, %{op: :let_in, name: "a"}} = GeneratedExpressionParser.parse(source)
  end

  test "validate accepts first binding on let line when in is on its own line" do
    source = """
    let counter = n + 1
    in
    counter + 2
    """

    assert :ok = LetLayout.validate(source)
    assert {:ok, _} = GeneratedExpressionParser.parse(source)
  end

  test "parses nested let in case branch after normalization" do
    source = """
    let
        batteryOps =
            case model.batteryLevel of
                Nothing ->
                    []

                Just batteryLevel ->
                    let
                        batteryColor =
                            if batteryLevel <= 20 then
                                PebbleColor.red

                            else if batteryLevel <= 40 then
                                PebbleColor.chromeYellow

                            else
                                PebbleColor.green
                    in
                    []
    in
    []
        |> PebbleUi.toUiNode
    """

    assert {:ok, %{op: :let_in}} = GeneratedExpressionParser.parse(source)
  end

  test "GeneratedExpressionParser normalizes inline let/in before parsing" do
    assert {:ok, %{op: :let_in}} =
             GeneratedExpressionParser.parse("let base = helper n in base + 1")
  end

  test "normalizes let when in is at end of line and body follows on next line" do
    source = "let appended = String.append left right in\n    String.length appended"

    assert {:ok, %{op: :let_in, name: "appended"}} = GeneratedExpressionParser.parse(source)
  end

  test "parses tangram companion update with nested case in branch" do
    source = """
    case msg of
        CatalogReceived (Ok json) ->
            case catalogNames json of
                [] ->
                    ( model, Cmd.none )

                names ->
                    ( { model | names = names }, Cmd.none )

        SvgReceived (Ok svg) ->
            let
                figureId =
                    model.figure

                pieces =
                    parseSvgPieces svg
            in
            case pieces of
                [] ->
                    ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        SvgReceived (Err _) ->
            ( model, Cmd.none )
    """

    assert {:ok, %{op: :case}} = GeneratedExpressionParser.parse(source)
  end

  test "parses List.concat with embedded case and trailing pipe" do
    source = """
    let
        cx =
            model.screenW // 2

        figure =
            case model.companionFigure of
                Just companionFigure ->
                    companionFigure

                Nothing ->
                    minute
    in
    List.concat
        [ [ Ui.clear Color.white
          , Ui.circle { x = cx, y = cy } 60 Color.black
          ]
        , case model.downloadedPieces of
            [] ->
                [ Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 0, y = 0, w = 10, h = 10 } "x" ]

            pieces ->
                pieces
        , [ Ui.fillCircle { x = 1, y = 2 } 4 Color.white
          , Ui.fillCircle { x = 3, y = 4 } 3 Color.white
          ]
        |> Ui.toUiNode
    """

    assert {:ok, %{op: :let_in}} = GeneratedExpressionParser.parse(source)
  end

  test "parses postfix field access on parenthesized expression" do
    assert {:ok, %{op: :qualified_call, target: "String.fromInt", args: [arg]}} =
             GeneratedExpressionParser.parse("String.fromInt (compute 42).y")

    assert %{op: :field_access, field: "y", arg: %{op: :call, name: "compute"}} = arg
  end

  test "parses parenthesized constructor pattern in cons case branch" do
    source = """
    case list of
        (Wrapped InnerA) :: [] ->
            "single-wrapped-A"
        _ ->
            "other"
    """

    assert {:ok, %{op: :case, branches: branches}} = GeneratedExpressionParser.parse(source)
    [%{pattern: %{kind: :constructor, name: "::", arg_pattern: %{kind: :tuple, elements: [head, _tail]}}} | _] =
      branches

    assert %{kind: :constructor, name: "Wrapped", arg_pattern: %{kind: :constructor, name: "InnerA"}} = head
  end

  test "parses wildcard tuple destructuring in multiline let" do
    source = """
    let
        msg = update model
        ( _, paths ) = msg
    in
    paths
    """

    assert {:ok, %{op: :let_in}} = GeneratedExpressionParser.parse(source)
  end

  test "parses discard wildcard binding in let" do
    source = """
    let
        _ =
            value
    in
    0
    """

    assert {:ok, %{op: :let_in, name: "_"}} = GeneratedExpressionParser.parse(source)
  end

  test "parses discard wildcard binding inside case branch" do
    source = """
    case msg of
        BatteryChanged value ->
            let
                _ =
                    value
            in
            ( model, Cmd.none )
    """

    assert {:ok, %{op: :case}} = GeneratedExpressionParser.parse(source)
  end

  test "parses constructor pattern binding after multiline let value" do
    source = """
    \\title build (Schema data) ->
        let
            start =
                Schema { data | currentSection = Just title, sections = data.sections ++ [ Section title [] ] }

            (Schema next) =
                build start
        in
        Schema { next | currentSection = data.currentSection }
    """

    assert {:ok, %{op: :lambda}} = GeneratedExpressionParser.parse(source)
  end

  test "parses scientific notation float literals" do
    assert {:ok, %{op: :float_literal, value: 5.0e-324}} =
             GeneratedExpressionParser.parse("5.0e-324")

    assert {:ok, %{op: :float_literal}} = GeneratedExpressionParser.parse("1.0e-300")
  end

  test "parses leading-zero decimal float literals" do
    assert {:ok, %{op: :float_literal, value: 0.9856}} =
             GeneratedExpressionParser.parse("0.9856")

    assert {:ok, %{op: :float_literal, value: 0.020}} =
             GeneratedExpressionParser.parse("0.020")

    assert {:error, {:invalid_number_literal, :leading_zero}} =
             GeneratedExpressionParser.parse("012")
  end

  test "parses unary minus after comparison operators" do
    assert {:ok, %{op: :compare, kind: :lt, right: %{op: :call, name: "negate"}}} =
             GeneratedExpressionParser.parse("normalized < -pi")
  end

  test "parses operator sections for apL and apR" do
    assert {:ok, %{op: :var, name: "<|"}} = GeneratedExpressionParser.parse("(<|)")
    assert {:ok, %{op: :var, name: "|>"}} = GeneratedExpressionParser.parse("(|>)")
    assert {:ok, %{op: :call, name: "|>"}} = GeneratedExpressionParser.parse("(|>) 10 f")
  end

  test "parses field accessor composition without breaking .term" do
    source = "Maybe.map (.term >> blockRefs)"

    assert {:ok, %{op: :qualified_call, target: "Maybe.map"}} =
             GeneratedExpressionParser.parse(source)
  end

  test "parses lambda tuple pattern with trailing wildcards" do
    source = "\\( revEntries, _, _ ) -> List.reverse revEntries"

    assert {:ok, %{op: :lambda}} = GeneratedExpressionParser.parse(source)
  end

  test "GeneratedExpressionParser preserves triple-quoted string contents" do
    source = ~S|D.decodeString (D.field "name" D.string) """{"name": "Alice"}"""|

    assert {:ok,
            %{
              op: :qualified_call,
              target: "D.decodeString",
              args: [_, %{op: :string_literal, value: ~s|{"name": "Alice"}|}]
            }} = GeneratedExpressionParser.parse(source)
  end

  test "parses nested case expression as outer case branch body" do
    source = """
    case msg of
        MinuteChanged minute ->
            case model.now of
                Nothing ->
                    ( model, Cmd.none )

                Just now ->
                    ( { model | now = Just { now | minute = minute } }
                    , Cmd.none
                    )
    """

    assert {:ok, %{op: :case, branches: branches}} = GeneratedExpressionParser.parse(source)
    assert length(branches) == 1
    assert match?(%{pattern: %{name: "MinuteChanged"}}, hd(branches))
  end

  test "starter watch template Main.elm parses through generated frontend" do
    path =
      Path.expand(
        "../../ide/priv/project_templates/starter_watch/src/Main.elm",
        __DIR__
      )

    if File.exists?(path) do
      assert {:ok, module} = GeneratedParser.parse_file(path)
      assert module.name == "Main"
      assert Enum.any?(module.declarations, &(&1.name == "handleAppMsg"))
    else
      assert true
    end
  end
end
