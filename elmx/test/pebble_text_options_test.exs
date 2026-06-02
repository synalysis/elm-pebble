defmodule Elmx.PebbleTextOptionsTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Pebble.TextOptions
  alias Elmx.Runtime.Pebble.Ui
  alias Elmx.Runtime.ViewOutput

  test "fields reads align_left and align_right context settings" do
    assert TextOptions.fields([]) == {"center", "word_wrap"}

    assert TextOptions.fields(%{
             "type" => "contextSetting",
             "key" => "align_left",
             "value" => []
           }) == {"left", "word_wrap"}

    assert TextOptions.fields(%{
             "type" => "contextSetting",
             "key" => "align_right",
             "value" => []
           }) == {"right", "word_wrap"}
  end

  test "fields walks nested context settings" do
    nested = %{
      "type" => "contextSetting",
      "key" => "trailing_ellipsis",
      "value" => %{"type" => "contextSetting", "key" => "align_left", "value" => []}
    }

    assert TextOptions.fields(nested) == {"left", "trailing_ellipsis"}
  end

  test "from_view_tree preserves text alignment from runtime options" do
    tree =
      Ui.to_ui_node([
        Ui.text(:font, [], %{x: 0, y: 0, w: 100, h: 20}, "Centered"),
        Ui.text(
          :font,
          %{"type" => "contextSetting", "key" => "align_left", "value" => []},
          %{x: 4, y: 24, w: 96, h: 20},
          "Left"
        ),
        Ui.text(
          :font,
          %{"type" => "contextSetting", "key" => "align_right", "value" => []},
          %{x: 4, y: 48, w: 96, h: 20},
          "Right"
        )
      ])

    rows = ViewOutput.from_view_tree(tree)

    assert Enum.find(rows, &(&1["text"] == "Centered"))["text_align"] == "center"
    assert Enum.find(rows, &(&1["text"] == "Left"))["text_align"] == "left"
    assert Enum.find(rows, &(&1["text"] == "Right"))["text_align"] == "right"
  end
end
