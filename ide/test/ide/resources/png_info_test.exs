defmodule Ide.Resources.PngInfoTest do
  use ExUnit.Case, async: true

  alias Ide.Resources.PngInfo

  @mono Path.expand(
          "../../../priv/project_templates/watch_demo_drawing_showcase/resources/bitmaps/BitmapStaticBtIcon.png",
          __DIR__
        )

  test "color_palette_image? is false for 1-bit indexed png" do
    refute PngInfo.color_palette_image?(File.read!(@mono))
  end

  test "color_palette_image? is true for truecolor png" do
    path = System.tmp_dir!() |> Path.join("png_info_color_#{System.unique_integer([:positive])}.png")

    if bin = System.find_executable("magick") || System.find_executable("convert") do
      args =
        if String.ends_with?(Path.basename(bin), "magick"),
          do: ["-size", "8x8", "gradient:red-blue", "-type", "TrueColor", "PNG32:" <> path],
          else: ["-size", "8x8", "gradient:red-blue", "-type", "TrueColor", path]

      {_, 0} = System.cmd(bin, args, stderr_to_stdout: true)

      assert {:ok, %{color_type: color_type, bit_depth: bit_depth}} = PngInfo.ihdr(File.read!(path))
      assert color_type in [2, 6] or (color_type == 3 and bit_depth > 1)
      assert PngInfo.color_palette_image?(File.read!(path))
    else
      assert true
    end

    File.rm(path)
  end
end
