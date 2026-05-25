defmodule ElmExecutor.Runtime.PebbleUiToUiNodeTest do
  use ExUnit.Case, async: true

  alias ElmExecutor.Runtime.CoreIREvaluator

  test "unknown Pebble.Ui.toUiNode wraps render-op lists for runtime view evaluation" do
    ops = [
      %{"type" => "bitmapInRect", "children" => [], "label" => ""}
    ]

    context = %{module: "Main", functions: %{}}

    expr = %{
      "op" => :qualified_call,
      "target" => "Pebble.Ui.toUiNode",
      "args" => [ops]
    }

    assert {:ok, %{"type" => "windowStack"} = tree} =
             CoreIREvaluator.evaluate(expr, %{}, context)

    assert is_list(tree["children"])
  end
end
