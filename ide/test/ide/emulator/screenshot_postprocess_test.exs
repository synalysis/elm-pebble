defmodule Ide.Emulator.ScreenshotPostprocessTest do
  use ExUnit.Case, async: true

  alias Ide.Emulator.ScreenshotPostprocess

  test "round mask clears pixels outside the circle" do
    {width, height} = {4, 4}
    inside = <<0, 0, 255, 255>>
    pixels = :binary.copy(inside, width * height)

    profile = %{
      "shape" => "round",
      "color_mode" => "Color",
      "screen" => %{"width" => width, "height" => height}
    }

    assert {:ok, masked} = ScreenshotPostprocess.apply_shape_mask(pixels, width, height, profile)

    assert corner_pixel(masked, width, 0, 0) == <<0, 0, 0, 0>>
    assert corner_pixel(masked, width, 1, 1) == inside
  end

  test "trim_content_margins removes leading blank margins" do
    blank = <<0, 0, 0, 255>>
    content = <<100, 120, 140, 255>>

    pixels =
      for y <- 0..5, x <- 0..5, into: <<>> do
        if x == 0 or y == 0, do: blank, else: content
      end

    profile = %{
      "shape" => "rect",
      "color_mode" => "Color",
      "screen" => %{"width" => 6, "height" => 6}
    }

    assert {:ok, trimmed, 5, 5} =
             ScreenshotPostprocess.trim_content_margins(pixels, 6, 6, profile)

    assert byte_size(trimmed) == 5 * 5 * 4
    assert :binary.part(trimmed, 0, 4) == content
  end

  test "trim_content_margins removes black letterboxing on bw watches" do
    margin = <<0, 0, 0, 255>>
    content = <<200, 200, 200, 255>>

    pixels =
      for y <- 0..5, x <- 0..5, into: <<>> do
        if x == 0 or y == 0, do: margin, else: content
      end

    profile = %{
      "shape" => "rect",
      "color_mode" => "BlackWhite",
      "screen" => %{"width" => 6, "height" => 6}
    }

    assert {:ok, trimmed, 5, 5} =
             ScreenshotPostprocess.trim_content_margins(pixels, 6, 6, profile)

    assert byte_size(trimmed) == 5 * 5 * 4
  end

  test "trim and resize expands inset round content to target size" do
    blank = <<0, 0, 0, 0>>
    inside = <<200, 100, 50, 255>>
    side = 100
    margin = 40

    pixels =
      for y <- 0..(side + 2 * margin - 1), into: <<>> do
        for x <- 0..(side + 2 * margin - 1), into: <<>> do
          if x >= margin and x < margin + side and y >= margin and y < margin + side do
            inside
          else
            blank
          end
        end
      end

    profile = %{
      "shape" => "round",
      "color_mode" => "Color",
      "screen" => %{"width" => 180, "height" => 180}
    }

    fb = side + 2 * margin

    assert {:ok, trimmed, trim_w, trim_h} =
             ScreenshotPostprocess.trim_content_margins(pixels, fb, fb, profile)

    assert trim_w == 180
    assert trim_h == 180
    assert {:ok, resized} = ScreenshotPostprocess.resize_bgrx(trimmed, trim_w, trim_h, 180, 180)
    assert byte_size(resized) == 180 * 180 * 4
  end

  test "screen_size uses store dimensions for gabbro" do
    assert ScreenshotPostprocess.screen_size("gabbro") == {260, 260}
  end

  test "crop removes padded rows from a wider VNC framebuffer" do
    src_w = 6
    src_h = 2
    dst_w = 4
    dst_h = 2

    pixels =
      for y <- 0..(src_h - 1), x <- 0..(src_w - 1), into: <<>> do
        <<x, y, 0, 255>>
      end

    assert {:ok, cropped} =
             ScreenshotPostprocess.crop_framebuffer(pixels, src_w, src_h, dst_w, dst_h)

    assert byte_size(cropped) == dst_w * dst_h * 4
    assert :binary.part(cropped, 0, 4) == <<0, 0, 0, 255>>
    assert :binary.part(cropped, 4, 4) == <<1, 0, 0, 255>>
  end

  defp corner_pixel(pixels, width, x, y) do
    :binary.part(pixels, (y * width + x) * 4, 4)
  end
end
