defmodule ElmEx.Frontend.GeneratedContractBuilderTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.GeneratedContractBuilder

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
end
