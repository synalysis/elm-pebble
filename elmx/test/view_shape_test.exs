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

  test "normalizes flattened Line ctor args from lowered RenderOp" do
    line = %{"ctor" => "Line", "args" => [72, 84, 30, 60, 192]}

    tree =
      ViewShape.normalize([
        %{"type" => "clear", "color" => 255},
        line
      ])

    assert %{"type" => "windowStack", "children" => [window]} = tree
    assert %{"type" => "window", "children" => [_expr, layer]} = window
    assert %{"type" => "canvasLayer", "children" => ops} = layer

    assert %{"type" => "line", "x1" => 72, "y1" => 84, "x2" => 30, "y2" => 60} =
             Enum.find(ops, &(&1["type"] == "line"))
  end

  test "normalizes tagged tuples from compiled elixir view ADTs" do
    path = {:Path, [%{x: 20, y: 70}, %{x: 60, y: 70}, %{x: 40, y: 30}], %{x: 0, y: 0}, 0}

    tree =
      ViewShape.normalize([
        {:Clear, 255},
        {:Group,
         {:Context,
          [{:StrokeWidth, 2}, {:StrokeColor, 192}, {:FillColor, 248}],
          [{:PathFilled, path}, {:PathOutline, path}]}}
      ])

    assert %{"type" => "windowStack"} = tree

    types =
      tree
      |> collect_view_types([])
      |> MapSet.new()

    assert "pathFilled" in types
    assert "pathOutline" in types
  end

  defp collect_view_types(nodes, acc) when is_list(nodes) do
    Enum.reduce(nodes, acc, fn node, a -> collect_view_types(node, a) end)
  end

  defp collect_view_types(%{"type" => type, "children" => children}, acc) when is_list(children) do
    collect_view_types(children, [type | acc])
  end

  defp collect_view_types(%{"type" => type}, acc), do: [type | acc]
  defp collect_view_types(%{type: type, children: children}, acc) when is_list(children) do
    collect_view_types(children, [to_string(type) | acc])
  end

  defp collect_view_types(%{type: type}, acc), do: [to_string(type) | acc]
  defp collect_view_types(_node, acc), do: acc

  test "normalizes PathFilled ctor ops into canvas draw ops" do
    path = %{
      "ctor" => "Path",
      "args" => [
        [%{"x" => 20, "y" => 70}, %{"x" => 60, "y" => 70}, %{"x" => 40, "y" => 30}],
        %{"x" => 0, "y" => 0},
        0
      ]
    }

    tree =
      ViewShape.normalize([
        %{"type" => "clear", "color" => 255},
        %{"ctor" => "PathFilled", "args" => [path]}
      ])

    assert %{"type" => "windowStack", "children" => [window]} = tree
    assert %{"type" => "window", "children" => [_expr, layer]} = window
    assert %{"type" => "canvasLayer", "children" => ops} = layer

    assert %{"type" => "pathFilled", "path" => %{"type" => "path", "points" => points}} =
             Enum.find(ops, &(&1["type"] == "pathFilled"))

    assert length(points) == 3
  end

  test "normalizes bare render op lists into a default window canvas tree" do
    ops = [
      %{"type" => "clear", "color" => 0xFFFFFFFF},
      %{"type" => "circle", "cx" => 72, "cy" => 84, "r" => 60, "color" => 0}
    ]

    assert %{"type" => "windowStack", "children" => [window]} = ViewShape.normalize(ops)
    assert %{"type" => "window", "children" => [_expr, layer]} = window
    assert %{"type" => "canvasLayer", "children" => canvas_ops} = layer
    assert %{"type" => "circle", "cx" => 72, "cy" => 84} = Enum.find(canvas_ops, &(&1["type"] == "circle"))
  end
end
