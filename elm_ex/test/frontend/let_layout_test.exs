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
