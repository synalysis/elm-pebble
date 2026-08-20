defmodule Ide.Pebble.TextLayoutTest do
  use ExUnit.Case, async: true

  alias Ide.Pebble.TextLayout

  test "lifts a 14px face in a 16px date window off the bottom stroke" do
    assert TextLayout.center_aligned_lift(16, 14) == 3
  end

  test "lifts a tight same-size box so baseline ink is not on the stroke" do
    assert TextLayout.center_aligned_lift(18, 18) == 3
  end

  test "leaves tall time bands top-aligned" do
    assert TextLayout.center_aligned_lift(52, 42) == 0
  end

  test "does not lift system-fallback fonts with no declared height" do
    assert TextLayout.center_aligned_lift(16, 0) == 0
    assert TextLayout.center_aligned_lift(12, 0) == 0
  end

  test "origin y matches the emulator GRect lift" do
    assert TextLayout.center_aligned_origin_y(80, 16, 14) == 77
    assert TextLayout.center_aligned_origin_y(0, 52, 42) == 0
  end
end
