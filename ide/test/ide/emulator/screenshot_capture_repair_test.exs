defmodule Ide.Emulator.ScreenshotCaptureRepairTest do
  use ExUnit.Case, async: true

  alias Ide.Emulator.ScreenshotCaptureRepair

  test "normalize_dimensions upscales legacy smaller gabbro captures to store size" do
    rgb = :binary.copy(<<255, 0, 0>>, 180 * 180 * 3)
    {out, w, h} = ScreenshotCaptureRepair.normalize_dimensions(rgb, 180, 180, "gabbro")
    assert {w, h} == {260, 260}
    assert byte_size(out) == 260 * 260 * 3
  end

  test "normalize_dimensions leaves full-size gabbro captures unchanged" do
    rgb = :binary.copy(<<255, 0, 0>>, 260 * 260 * 3)
    {out, w, h} = ScreenshotCaptureRepair.normalize_dimensions(rgb, 260, 260, "gabbro")
    assert {w, h} == {260, 260}
    assert out == rgb
  end

  test "shift_top_left_bezel removes asymmetric top and left black edges" do
    width = 4
    height = 4

    rgb =
      for y <- 0..(height - 1), x <- 0..(width - 1), into: <<>> do
        cond do
          x == 0 or y == 0 -> <<0, 0, 0>>
          x == 2 and y == 2 -> <<255, 0, 0>>
          true -> <<255, 255, 255>>
        end
      end

    {repaired, ^width, ^height} =
      ScreenshotCaptureRepair.repair_rgb(rgb, width, height, "basalt", normalize: false)

    assert pixel_rgb(repaired, width, 0, 0) == {255, 255, 255}
    assert pixel_rgb(repaired, width, 3, 3) == {255, 0, 0}
  end

  test "repair_rgba preserves interior black that touches a border beyond letterbox depth" do
    width = 16
    height = 16

    rgba =
      for y <- 0..(height - 1), x <- 0..(width - 1), into: <<>> do
        cond do
          x >= div(width, 2) and y >= div(height, 2) -> <<0, 0, 0, 255>>
          true -> <<255, 255, 255, 255>>
        end
      end

    out = ScreenshotCaptureRepair.repair_rgba(rgba, width, height, "diorite")
    assert pixel_rgba(out, width, 10, 10) == {0, 0, 0, 255}
  end

  test "repair_rgba floods rect monochrome corner letterbox to white" do
    width = 4
    height = 4

    rgba =
      for y <- 0..(height - 1), x <- 0..(width - 1), into: <<>> do
        if x == 1 and y == 1, do: <<0, 0, 0, 255>>, else: <<255, 255, 255, 255>>
      end

    out = ScreenshotCaptureRepair.repair_rgba(rgba, width, height, "diorite")
    assert pixel_rgba(out, width, 0, 0) == {255, 255, 255, 255}
    assert pixel_rgba(out, width, 1, 1) == {0, 0, 0, 255}
  end

  test "repair_rgba clears round black pixels outside the display circle" do
    width = 8
    height = 8
    rgba = :binary.copy(<<0, 0, 0, 255>>, width * height * 4)

    out = ScreenshotCaptureRepair.repair_rgba(rgba, width, height, "chalk")
    assert pixel_rgba(out, width, 0, 0) == {0, 0, 0, 0}
    assert pixel_rgba(out, width, 4, 4) == {0, 0, 0, 255}
  end

  test "repair_rgba clears round black pixels adjacent to transparent corners" do
    width = 6
    height = 6

    rgba =
      for y <- 0..(height - 1), x <- 0..(width - 1), into: <<>> do
        cond do
          x == 0 and y == 0 -> <<0, 0, 0, 0>>
          x == 1 and y == 0 -> <<0, 0, 0, 255>>
          x == 0 and y == 1 -> <<0, 0, 0, 255>>
          true -> <<255, 255, 255, 255>>
        end
      end

    out = ScreenshotCaptureRepair.repair_rgba(rgba, width, height, "gabbro")
    assert pixel_rgba(out, width, 1, 0) == {0, 0, 0, 0}
    assert pixel_rgba(out, width, 0, 1) == {0, 0, 0, 0}
    assert pixel_rgba(out, width, 2, 2) == {255, 255, 255, 255}
  end

  defp pixel_rgb(rgb, width, x, y) do
    <<r, g, b>> = :binary.part(rgb, (y * width + x) * 3, 3)
    {r, g, b}
  end

  defp pixel_rgba(rgba, width, x, y) do
    <<r, g, b, a>> = :binary.part(rgba, (y * width + x) * 4, 4)
    {r, g, b, a}
  end
end
