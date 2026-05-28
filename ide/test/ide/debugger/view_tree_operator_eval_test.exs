defmodule Ide.Debugger.ViewTreeOperatorEvalTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.ElmIntrospect
  alias ElmExecutor.Runtime.SemanticExecutor

  test "modBy in view tree evaluates for layout coordinates" do
    source = """
    module Main exposing (view)

    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    view model =
        Ui.root
            [ Ui.fillRect { x = modBy 10 model.x, y = 0, w = 8, h = 8 } Color.black
            ]
    """

    assert {:ok, %{"elm_introspect" => ei}} = ElmIntrospect.analyze_source(source, "Main.elm")

    rows =
      SemanticExecutor.derive_view_output_preview(
        ei["view_tree"],
        %{"x" => 23, "screenW" => 144, "screenH" => 168},
        %{elm_introspect: ei}
      )

    rect = Enum.find(rows, &(&1["kind"] == "fill_rect"))
    assert rect
    assert rect["x"] == 3
  end

  test "internal arithmetic calls use type call in introspect view tree" do
    source = """
    module Main exposing (view)

    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    view model =
        let
            y = (model.screenH - 20) // 2
        in
        Ui.root [ Ui.fillRect { x = 0, y = y, w = 10, h = 10 } Color.black ]
    """

    assert {:ok, %{"elm_introspect" => ei}} = ElmIntrospect.analyze_source(source, "Main.elm")

    rows =
      SemanticExecutor.derive_view_output_preview(
        ei["view_tree"],
        %{"screenH" => 168, "screenW" => 144},
        %{elm_introspect: ei}
      )

    rect = Enum.find(rows, &(&1["kind"] == "fill_rect"))
    assert rect
    assert rect["y"] == 74
  end

  test "if in view tree picks then or else branch for layout x" do
    source = """
    module Main exposing (view)

    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    view model =
        Ui.root
            [ Ui.fillRect { x = if model.useWide then 10 else 20, y = 0, w = 8, h = 8 } Color.black
            ]
    """

    assert {:ok, %{"elm_introspect" => ei}} = ElmIntrospect.analyze_source(source, "Main.elm")

    wide_rows =
      SemanticExecutor.derive_view_output_preview(
        ei["view_tree"],
        %{"useWide" => true, "screenW" => 144, "screenH" => 168},
        %{elm_introspect: ei}
      )

    narrow_rows =
      SemanticExecutor.derive_view_output_preview(
        ei["view_tree"],
        %{"useWide" => false, "screenW" => 144, "screenH" => 168},
        %{elm_introspect: ei}
      )

    assert Enum.find(wide_rows, &(&1["kind"] == "fill_rect"))["x"] == 10
    assert Enum.find(narrow_rows, &(&1["kind"] == "fill_rect"))["x"] == 20
  end

  test "model.isColor toggles layout branch for fillRect width" do
    source = """
    module Main exposing (view)

    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    view model =
        Ui.root
            [ Ui.fillRect { x = 0, y = 0, w = if model.isColor then 16 else 8, h = 8 } Color.black
            ]
    """

    assert {:ok, %{"elm_introspect" => ei}} = ElmIntrospect.analyze_source(source, "Main.elm")

    wide =
      SemanticExecutor.derive_view_output_preview(
        ei["view_tree"],
        %{"isColor" => true, "screenW" => 144, "screenH" => 168},
        %{elm_introspect: ei}
      )
      |> Enum.find(&(&1["kind"] == "fill_rect"))

    narrow =
      SemanticExecutor.derive_view_output_preview(
        ei["view_tree"],
        %{"isColor" => false, "screenW" => 144, "screenH" => 168},
        %{elm_introspect: ei}
      )
      |> Enum.find(&(&1["kind"] == "fill_rect"))

    assert wide["w"] == 16
    assert narrow["w"] == 8
  end
end
