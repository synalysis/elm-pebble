defmodule Ide.ScreenshotDimensionsTest do
  use ExUnit.Case, async: true

  alias Ide.ScreenshotDimensions

  test "store dimensions include gabbro at 260x260" do
    assert ScreenshotDimensions.store_dimensions("gabbro") == {260, 260}
    assert ScreenshotDimensions.store_dimensions("basalt") == {144, 168}
  end

  test "normalize_for_store upscales gabbro emulator captures" do
    png = sample_png(180, 180)

    assert {:ok, normalized} = ScreenshotDimensions.normalize_for_store(png, "gabbro")
    assert ScreenshotDimensions.valid_store_file?("gabbro", normalized)
  end

  test "normalize_for_store is a no-op for unknown platforms" do
    png = sample_png(100, 100)
    assert {:ok, ^png} = ScreenshotDimensions.normalize_for_store(png, "embedded")
  end

  defp sample_png(width, height) do
    raw =
      for _y <- 0..(height - 1), into: <<>> do
        <<0>> <> :binary.copy(<<1, 2, 3, 255>>, width)
      end
      |> IO.iodata_to_binary()
      |> :zlib.compress()

    ihdr = <<width::unsigned-big-32, height::unsigned-big-32, 8, 6, 0, 0, 0>>

    IO.iodata_to_binary([
      <<137, 80, 78, 71, 13, 10, 26, 10>>,
      chunk("IHDR", ihdr),
      chunk("IDAT", raw),
      chunk("IEND", <<>>)
    ])
  end

  defp chunk(type, data) do
    crc = :erlang.crc32(type <> data)

    <<
      byte_size(data)::unsigned-big-32,
      type::binary,
      data::binary,
      crc::unsigned-big-32
    >>
  end
end
