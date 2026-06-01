defmodule Elmx.ViewShapeTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.ViewShape

  test "normalizes tagged WindowStack values from lowered IR" do
    node = {1000, [{1001, {1, []}}]}
    normalized = ViewShape.normalize(node)
    assert normalized["type"] == "windowStack"
  end

  test "normalizes WindowStack ctor trees like Pebble.Ui.windowStack" do
    node = %{"ctor" => "WindowStack", "args" => [[%{"ctor" => "WindowNode", "args" => [1, []]}]]}

    assert %{"type" => "windowStack", "children" => [_window]} = ViewShape.normalize(node)
  end

  test "normalizes user-named wrapper that returns the same ctor shape" do
    wrapped =
      %{
        "ctor" => "WindowStack",
        "args" => [
          [
            %{
              "ctor" => "WindowNode",
              "args" => [
                1,
                [%{"ctor" => "CanvasLayer", "args" => [1, [%{"ctor" => "Clear", "args" => [0]}]]}]
              ]
            }
          ]
        ]
      }

    assert %{"type" => "windowStack"} = ViewShape.normalize(wrapped)
  end
end
