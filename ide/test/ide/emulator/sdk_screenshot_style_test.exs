defmodule Ide.Emulator.SdkScreenshotStyleTest do
  use ExUnit.Case, async: true

  alias Ide.Emulator.SdkScreenshotStyle

  test "process produces valid png" do
    width = 4
    height = 4
    rgb = :binary.copy(<<255, 0, 0>>, width * height)

    assert {:ok, png} = SdkScreenshotStyle.process("chalk", rgb, width, height)
    assert byte_size(png) > 24
    assert :binary.part(png, 0, 8) == <<137, 80, 78, 71, 13, 10, 26, 10>>
  end

  test "correct_colours remaps pebble palette values on all platforms" do
    assert SdkScreenshotStyle.correct_colours(<<0, 0, 85>>) == <<0, 30, 65>>
    assert SdkScreenshotStyle.correct_colours(<<85, 85, 85>>) == <<84, 84, 84>>
  end

  test "roundify makes square corners transparent on chalk" do
    width = 180
    height = 180
    rgb = :binary.copy(<<0, 0, 0>>, width * height * 3)

    assert {:ok, rgba} = SdkScreenshotStyle.build_rgba("chalk", rgb, width, height)
    assert pixel(rgba, width, 90, 90) == {0, 0, 0, 255}
    assert pixel(rgba, width, 5, 5) == {0, 0, 0, 0}
  end

  test "rect monochrome applies sdk colour correction and clears corner letterbox" do
    rgb =
      for y <- 0..1, x <- 0..1, into: <<>> do
        if x == 0 and y == 0, do: <<0, 0, 0>>, else: <<85, 85, 85>>
      end

    assert {:ok, rgba} =
             SdkScreenshotStyle.build_rgba("diorite", rgb, 2, 2, normalize: false)

    assert pixel(rgba, 2, 0, 0) == {255, 255, 255, 255}
    assert pixel(rgba, 2, 1, 1) == {84, 84, 84, 255}
  end

  test "diorite white stays white after sdk colour correction" do
    white = :binary.copy(<<255, 255, 255>>, 2 * 2)

    assert {:ok, rgba} =
             SdkScreenshotStyle.build_rgba("diorite", white, 2, 2, normalize: false)

    assert rgba == <<255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255>>
  end

  test "gabbro roundify clears corner pixels" do
    width = 180
    height = 180
    rgb = :binary.copy(<<255, 0, 0>>, width * height * 3)

    assert {:ok, rgba} = SdkScreenshotStyle.build_rgba("gabbro", rgb, width, height)
    assert pixel(rgba, width, 90, 90) == {227, 84, 98, 255}
    assert pixel(rgba, width, 0, 0) == {0, 0, 0, 0}
  end

  defp pixel(rgba, width, x, y) do
    <<r, g, b, a>> = :binary.part(rgba, (y * width + x) * 4, 4)
    {r, g, b, a}
  end
end
