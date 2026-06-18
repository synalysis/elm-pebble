defmodule Ide.Resources.BitmapRasterTest do
  use ExUnit.Case, async: true

  alias Ide.Resources.BitmapRaster

  test "detect_format recognizes png and jpeg magic bytes" do
    assert BitmapRaster.detect_format(<<137, 80, 78, 71, 13, 10, 26, 10, 0>>) == :png
    assert BitmapRaster.detect_format(<<0xFF, 0xD8, 0xFF, 0xDB>>) == :jpeg
    assert BitmapRaster.detect_format("not an image") == :unknown
  end

  test "normalize_bytes keeps valid png unchanged" do
    png =
      <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 2, 0, 0, 0,
        3, 8, 2, 0, 0, 0, 217, 74, 34, 230, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>

    assert {:ok, %{bytes: ^png, width: 2, height: 3, converted: false}} =
             BitmapRaster.normalize_bytes(png)
  end

  test "normalize_for_import rejects unknown file types" do
    path = Path.join(System.tmp_dir!(), "bitmap_#{System.unique_integer([:positive])}.tiff")
    File.write!(path, "not-a-real-image")

    assert {:error, :unsupported_bitmap_type} =
             BitmapRaster.normalize_for_import("not-a-real-image", "logo.tiff")
  end

  @tag :imagemagick
  test "normalize_for_import converts jpeg bytes saved with a png extension" do
    unless Ide.Resources.BitmapMonochrome.imagemagick_bin() do
      flunk("ImageMagick required for this test")
    end

    jpeg_path = Path.join(System.tmp_dir!(), "bitmap_jpeg_#{System.unique_integer([:positive])}.jpg")
    bin = Ide.Resources.BitmapMonochrome.imagemagick_bin()

    args =
      if String.ends_with?(Path.basename(bin), "magick"),
        do: ["-size", "16x12", "xc:red", "JPEG:" <> jpeg_path],
        else: ["-size", "16x12", "xc:red", jpeg_path]

    {_, 0} = System.cmd(bin, args, stderr_to_stdout: true)
    jpeg_bytes = File.read!(jpeg_path)

    assert {:ok, prepared} =
             BitmapRaster.normalize_for_import(jpeg_bytes, "mislabeled.png")

    assert prepared.converted
    assert prepared.mime == "image/png"
    assert prepared.width > 0
    assert prepared.height > 0
    assert <<137, 80, 78, 71, 13, 10, 26, 10, _::binary>> = prepared.bytes
  end
end
