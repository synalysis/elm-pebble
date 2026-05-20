defmodule Ide.PngTest do
  use ExUnit.Case, async: true

  alias Ide.Png

  test "fit leaves matching dimensions unchanged" do
    png = sample_png(144, 168)

    assert {:ok, ^png} = Png.fit(png, 144, 168)
    assert {:ok, 144, 168} = Png.dimensions(png)
  end

  test "fit upscales emulator-sized gabbro captures to store dimensions" do
    png = sample_png(180, 180)

    assert {:ok, resized} = Png.fit(png, 260, 260)
    assert {:ok, 260, 260} = Png.dimensions(resized)
  end

  test "roundtrip encode preserves dimensions" do
    rgba =
      for _ <- 1..(4 * 4), into: <<>> do
        <<100, 120, 140, 255>>
      end

    assert {:ok, png} = encode_sample(rgba, 2, 2)
    assert {:ok, 2, 2} = Png.dimensions(png)
    assert {:ok, ^png} = Png.fit(png, 2, 2)
  end

  defp sample_png(width, height) do
    rgba =
      for _ <- 1..(width * height), into: <<>> do
        <<10, 20, 30, 255>>
      end

    {:ok, png} = encode_sample(rgba, width, height)
    png
  end

  defp encode_sample(rgba, width, height) do
    raw =
      for y <- 0..(height - 1), into: <<>> do
        row = :binary.part(rgba, y * width * 4, width * 4)
        <<0>> <> row
      end
      |> IO.iodata_to_binary()
      |> :zlib.compress()

    ihdr = <<width::unsigned-big-32, height::unsigned-big-32, 8, 6, 0, 0, 0>>

    {:ok,
     IO.iodata_to_binary([
       <<137, 80, 78, 71, 13, 10, 26, 10>>,
       chunk("IHDR", ihdr),
       chunk("IDAT", raw),
       chunk("IEND", <<>>)
     ])}
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
