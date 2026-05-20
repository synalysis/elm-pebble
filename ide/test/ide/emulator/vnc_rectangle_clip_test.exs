defmodule Ide.Emulator.VncRectangleClipTest do
  use ExUnit.Case, async: true

  alias Ide.Emulator.ScreenshotPostprocess

  test "row stride width matches emery padding" do
    assert ScreenshotPostprocess.row_stride_width_pixels(200) == 208
  end

  test "row stride width leaves 144px screens unchanged" do
    assert ScreenshotPostprocess.row_stride_width_pixels(144) == 144
  end
end
