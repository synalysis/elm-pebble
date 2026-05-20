defmodule Ide.Emulator.PebblePaletteTest do
  use ExUnit.Case, async: true

  alias Ide.Emulator.PebblePalette

  test "quantize_rgb snaps channels to pebble palette levels" do
    assert PebblePalette.quantize_rgb(<<80, 90, 100>>) == <<85, 85, 85>>
    assert PebblePalette.quantize_rgb(<<200, 10, 255>>) == <<170, 0, 255>>
  end
end
