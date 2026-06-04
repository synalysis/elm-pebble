defmodule Ide.Resources.BitmapMonochromeTest do
  use ExUnit.Case, async: true

  alias Ide.Resources.BitmapMonochrome

  @tag :imagemagick
  test "convert_bytes produces 1-bit png" do
    unless BitmapMonochrome.imagemagick_bin() do
      flunk("ImageMagick required for this test")
    end

    input = System.tmp_dir!() |> Path.join("bitmap_mono_in_#{System.unique_integer([:positive])}.png")
    bin = BitmapMonochrome.imagemagick_bin()

    args =
      if String.ends_with?(Path.basename(bin), "magick"),
        do: ["-size", "24x24", "gradient:red-blue", "PNG:" <> input],
        else: ["-size", "24x24", "gradient:red-blue", input]

    {_, 0} = System.cmd(bin, args, stderr_to_stdout: true)

    assert {:ok, bw_bytes} = BitmapMonochrome.convert_bytes(File.read!(input))
    assert byte_size(bw_bytes) > 0
    assert <<137, 80, 78, 71, 13, 10, 26, 10, _::binary>> = bw_bytes
    assert bw_bytes =~ "IHDR"

    File.rm(input)
  end
end
