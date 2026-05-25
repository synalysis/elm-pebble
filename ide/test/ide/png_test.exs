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

  test "fit decodes browser-style up-filtered pngs and resizes" do
    png = sample_png_with_filter(4, 4, 2)

    assert {:ok, resized} = Png.fit(png, 2, 2)
    assert {:ok, 2, 2} = Png.dimensions(resized)
  end

  test "fit decodes sub-filtered pngs" do
    png = sample_png_with_filter(4, 4, 1)

    assert {:ok, resized} = Png.fit(png, 4, 4)
    assert {:ok, 4, 4} = Png.dimensions(resized)
  end

  defp sample_png_with_filter(width, height, filter_type) do
    rgba =
      for y <- 0..(height - 1), x <- 0..(width - 1), into: <<>> do
        <<rem(x * 17 + y * 31, 256), rem(x * 13 + y * 7, 256), rem(x + y, 256), 255>>
      end

    row_bytes = width * 4

    raw =
      for y <- 0..(height - 1), reduce: {<<>>, nil} do
        {acc, prev_row} ->
          row = :binary.part(rgba, y * row_bytes, row_bytes)
          prev = prev_row || :binary.copy(<<0>>, row_bytes)
          filtered = filter_encode_row(row, prev, filter_type)
          {acc <> <<filter_type>> <> filtered, row}
      end
      |> elem(0)
      |> :zlib.compress()

    ihdr = <<width::unsigned-big-32, height::unsigned-big-32, 8, 6, 0, 0, 0>>

    IO.iodata_to_binary([
      <<137, 80, 78, 71, 13, 10, 26, 10>>,
      chunk("IHDR", ihdr),
      chunk("IDAT", raw),
      chunk("IEND", <<>>)
    ])
  end

  defp filter_encode_row(row, _prev, 1), do: sub_filter_encode(row)
  defp filter_encode_row(row, prev, 2), do: subtract_bytes(row, prev)
  defp filter_encode_row(row, _prev, _), do: row

  defp sub_filter_encode(row) do
    row_bytes = byte_size(row)

    for index <- 0..(row_bytes - 1), into: <<>> do
      current = :binary.at(row, index)
      left = if index < 4, do: 0, else: :binary.at(row, index - 4)
      <<rem(current - left + 256, 256)>>
    end
  end

  defp subtract_bytes(<<a, rest_a::binary>>, <<b, rest_b::binary>>) do
    <<rem(a - b + 256, 256)>> <> subtract_bytes(rest_a, rest_b)
  end

  defp subtract_bytes(<<>>, <<>>), do: <<>>

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
