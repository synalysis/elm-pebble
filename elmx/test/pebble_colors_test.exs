defmodule Elmx.PebbleColorsTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Pebble.Colors
  alias Elmx.Runtime.Pebble.Ui

  test "named colors use Pebble GColor8 constants" do
    assert Ui.named_color("white") == 0xFF
    assert Ui.named_color("black") == 0xC0
    assert Ui.named_color("green") == 0xCC
    assert Ui.named_color("chromeYellow") == 0xF8
    assert Ui.named_color("red") == 0xF0
  end

  test "to_int converts Indexed and legacy ARGB literals" do
    assert Colors.to_int(%{"ctor" => "Indexed", "args" => [0xCC]}) == 0xCC
    assert Colors.to_int(0xFF000000) == 0xC0
    assert Colors.to_int(0xFFFFFFFF) == 0xFF
  end

  test "clear and fill_rect emit GColor8 values" do
    assert %{color: 0xC0} = Ui.clear(:black)
    assert %{color: 0xCC} = Ui.fill_rect(%{x: 0, y: 0, w: 10, h: 2}, Ui.named_color("green"))
  end

  test "context color settings normalize to integers" do
    assert %{value: 0xFF} = Ui.context_setting("text_color", Ui.named_color("white"))
    assert %{value: 0xCC} = Ui.context_setting("fill_color", %{"ctor" => "Indexed", "args" => [0xCC]})
  end
end
