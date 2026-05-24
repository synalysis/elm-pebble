defmodule Ide.Resources.PebbleColorTest do
  use ExUnit.Case, async: true

  alias Ide.Resources.PebbleColor

  test "parse hex color to argb8" do
    assert PebbleColor.parse("#000000", 1.0) == 0xC0
    assert PebbleColor.parse("#FFFFFF", 1.0) == 0xFF
  end

  test "parse Pebble named colors" do
    assert PebbleColor.parse("black", 1.0) == 0xC0
    assert PebbleColor.parse("vividCerulean", 1.0) == 0xCB
    assert PebbleColor.parse("blueMoon", 1.0) == 0xC7
    assert PebbleColor.parse("cyan", 1.0) == 0xCF
  end

  test "transparent colors become clear" do
    assert PebbleColor.parse("none", 1.0) == 0
    assert PebbleColor.parse("black", 0.0) == 0
  end
end
