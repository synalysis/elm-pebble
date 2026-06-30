defmodule ElmEx.Frontend.GeneratedContractBuilderTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.GeneratedContractBuilder
  alias ElmEx.Frontend.GeneratedExpressionParser

  test "unindented line comments inside a function body do not truncate the definition" do
    source = """
    module Main exposing (view)

    view model =
        let
            cardW = model.screenW
        in
        PebbleUi.windowStack
            [ PebbleUi.window 1
                [ PebbleUi.canvasLayer 1
                    [ PebbleUi.clear PebbleColor.white
                    , PebbleUi.roundRect { x = 0, y = 0, w = cardW, h = 1 } 1 PebbleColor.black
    --                , PebbleUi.text UiResources.DefaultFont PebbleUi.defaultTextOptions { x = 0, y = 0, w = cardW, h = 1 } model.timeString
                    ]
                ]
            ]
    """

    view =
      "Main.elm"
      |> GeneratedContractBuilder.build(source, "Main", [])
      |> Map.get(:declarations)
      |> Enum.find(&(&1.kind == :function_definition and &1.name == "view"))

    assert view.expr[:op] == :let_in
    assert String.contains?(view.body, "]")
    refute match?(%{op: :unsupported}, view.expr)
  end

  test "block comment prose with equals signs is not parsed as function definitions" do
    source = """
    module InlineBoxIntCorruption exposing (main)

    {-| stores the value at `cursorReg + ELMVALUE_AS_INT_OFF` (= cursorReg + 8), but cursorReg
    points to the GcHeader base, not the ElmValue.
    -}

    pow2Loop acc n =
        acc

    main =
        pow2Loop 1 48
    """

    declarations =
      "InlineBoxIntCorruption.elm"
      |> GeneratedContractBuilder.build(source, "InlineBoxIntCorruption", [])
      |> Map.get(:declarations)

    names = Enum.map(declarations, & &1.name)
    assert "pow2Loop" in names
    assert "main" in names
    refute "at" in names
  end

  test "compose with qualified RHS parses as compose_left" do
    assert {:ok, %{op: :compose_left, f: %{target: "GotWeather"}, g: %{op: :qualified_call}}} =
             GeneratedExpressionParser.parse("GotWeather << Result.map Weather.Current")
  end
end
