defmodule Ide.Png do
  @moduledoc false

  @signature <<137, 80, 78, 71, 13, 10, 26, 10>>

  @spec dimensions(binary() | String.t()) :: {:ok, pos_integer(), pos_integer()} | :error
  def dimensions(path) when is_binary(path) do
    data =
      if byte_size(path) >= 24 and binary_part(path, 0, 8) == @signature do
        path
      else
        case File.read(path) do
          {:ok, bytes} -> bytes
          {:error, _} -> nil
        end
      end

    case data do
      nil ->
        :error

      <<@signature, _len::32, "IHDR", width::unsigned-big-32, height::unsigned-big-32, _::binary>> ->
        if width > 0 and height > 0, do: {:ok, width, height}, else: :error

      _ ->
        :error
    end
  end

  @doc """
  Resizes a truecolor RGBA PNG to `{width, height}` when needed.
  """
  @spec fit(binary(), pos_integer(), pos_integer()) :: {:ok, binary()} | {:error, term()}
  def fit(png, width, height) when is_binary(png) and width > 0 and height > 0 do
    case dimensions(png) do
      {:ok, ^width, ^height} ->
        {:ok, png}

      {:ok, src_w, src_h} ->
        with {:ok, rgba} <- decode_rgba(png),
             {:ok, resized} <- resize_rgba(rgba, src_w, src_h, width, height),
             {:ok, encoded} <- encode_rgba(resized, width, height) do
          {:ok, encoded}
        end

      :error ->
        {:error, :invalid_png}
    end
  end

  @spec decode_rgba(binary()) :: {:ok, binary()} | {:error, term()}
  defp decode_rgba(png) do
    with {:ok, width, height, _meta, idat} <- parse_chunks(png),
         {:ok, inflated} <- zlib_uncompress(idat),
         {:ok, rgba} <- unfilter_rgba(inflated, width, height) do
      {:ok, rgba}
    end
  end

  defp parse_chunks(png) do
    case png do
      <<@signature, rest::binary>> ->
        parse_chunks(rest, nil, nil, nil, <<>>)

      _ ->
        {:error, :invalid_png}
    end
  end

  defp parse_chunks(<<>>, width, height, _meta, idat)
       when is_integer(width) and is_integer(height) do
    {:ok, width, height, nil, idat}
  end

  defp parse_chunks(<<>>, _width, _height, _meta, _idat), do: {:error, :invalid_png}

  defp parse_chunks(<<length::unsigned-big-32, type::binary-size(4), data::binary-size(length),
                      crc::unsigned-big-32, rest::binary>>,
                     width,
                     height,
                     meta,
                     idat
                   ) do
    _ = crc

    case type do
      "IHDR" ->
        case data do
          <<w::unsigned-big-32, h::unsigned-big-32, 8, 6, 0, 0, 0>> ->
            parse_chunks(rest, w, h, meta, idat)

          _ ->
            {:error, :unsupported_png_format}
        end

      "IDAT" ->
        parse_chunks(rest, width, height, meta, idat <> data)

      "IEND" ->
        if is_integer(width) and is_integer(height) and byte_size(idat) > 0 do
          {:ok, width, height, meta, idat}
        else
          {:error, :invalid_png}
        end

      _ ->
        parse_chunks(rest, width, height, meta, idat)
    end
  end

  defp parse_chunks(_binary, _width, _height, _meta, _idat), do: {:error, :invalid_png}

  defp zlib_uncompress(data) do
    z = :zlib.open()

    try do
      :ok = :zlib.inflateInit(z)
      inflated = :zlib.inflate(z, data)
      :ok = :zlib.inflateEnd(z)
      {:ok, IO.iodata_to_binary(inflated)}
    catch
      :error, reason -> {:error, {:png_decompress_failed, reason}}
    after
      :zlib.close(z)
    end
  end

  defp unfilter_rgba(data, width, height) do
    row_bytes = width * 4
    expected = height * (row_bytes + 1)

    if byte_size(data) < expected do
      {:error, {:png_incomplete_image_data, byte_size(data), expected}}
    else
      rgba =
        Enum.reduce(0..(height - 1), <<>>, fn y, acc ->
          row = :binary.part(data, y * (row_bytes + 1), row_bytes + 1)
          <<filter, pixels::binary-size(row_bytes)>> = row
          unfiltered = unfilter_row(filter, pixels, acc, row_bytes, y)
          acc <> unfiltered
        end)

      {:ok, rgba}
    end
  end

  defp unfilter_row(0, pixels, _prev_rows, _row_bytes, _y), do: pixels

  defp unfilter_row(1, pixels, prev_rows, row_bytes, _y) do
    unfilter_sub(pixels, prev_row(prev_rows, row_bytes), row_bytes)
  end

  defp unfilter_row(2, pixels, prev_rows, row_bytes, y) do
    if y == 0 do
      pixels
    else
      unfilter_up(pixels, prev_row(prev_rows, row_bytes), row_bytes)
    end
  end

  defp unfilter_row(3, pixels, prev_rows, row_bytes, y) do
    prev = if y == 0, do: :binary.copy(<<0>>, row_bytes), else: prev_row(prev_rows, row_bytes)
    unfilter_average(pixels, prev, row_bytes)
  end

  defp unfilter_row(4, pixels, prev_rows, row_bytes, y) do
    prev = if y == 0, do: :binary.copy(<<0>>, row_bytes), else: prev_row(prev_rows, row_bytes)
    unfilter_paeth(pixels, prev, row_bytes)
  end

  defp unfilter_row(_unsupported, _pixels, _prev_rows, _row_bytes, _y),
    do: throw({:error, :unsupported_png_filter})

  defp prev_row(prev_rows, row_bytes) do
    :binary.part(prev_rows, byte_size(prev_rows) - row_bytes, row_bytes)
  end

  defp unfilter_sub(pixels, <<>>, row_bytes) do
    <<current::binary-size(row_bytes), rest::binary>> = pixels
    current <> unfilter_sub(rest, <<>>, row_bytes)
  end

  defp unfilter_sub(pixels, prev, row_bytes) do
    <<current::binary-size(row_bytes), rest::binary>> = pixels
    <<prev_row::binary-size(row_bytes), prev_rest::binary>> = prev
    fixed = add_bytes(current, prev_row)
    fixed <> unfilter_sub(rest, prev_rest, row_bytes)
  end

  defp unfilter_up(pixels, prev, row_bytes) do
    <<current::binary-size(row_bytes), rest::binary>> = pixels
    <<prev_row::binary-size(row_bytes), prev_rest::binary>> = prev
    fixed = add_bytes(current, prev_row)
    fixed <> unfilter_up(rest, prev_rest, row_bytes)
  end

  defp unfilter_average(pixels, prev, row_bytes) do
    unfilter_row_value(pixels, prev, <<>>, row_bytes, 0)
  end

  defp unfilter_row_value(<<>>, _prev, acc, _row_bytes, _index), do: acc

  defp unfilter_row_value(<<current, rest::binary>>, prev, acc, row_bytes, index) do
    left = if rem(index, row_bytes) == 0, do: 0, else: :binary.at(acc, byte_size(acc) - 1)
    up = if byte_size(prev) == 0, do: 0, else: :binary.at(prev, index)
    value = rem(current + div(left + up, 2), 256)
    unfilter_row_value(rest, prev, acc <> <<value>>, row_bytes, index + 1)
  end

  defp unfilter_paeth(pixels, prev, row_bytes) do
    unfilter_paeth_row(pixels, prev, <<>>, row_bytes, 0)
  end

  defp unfilter_paeth_row(<<>>, _prev, acc, _row_bytes, _index), do: acc

  defp unfilter_paeth_row(<<current, rest::binary>>, prev, acc, row_bytes, index) do
    left = if rem(index, row_bytes) == 0, do: 0, else: :binary.at(acc, byte_size(acc) - 1)
    up = if byte_size(prev) == 0, do: 0, else: :binary.at(prev, index)
    up_left = if rem(index, row_bytes) == 0 or byte_size(prev) == 0, do: 0, else: :binary.at(prev, index - 1)

    predictor =
      [left, up, up_left]
      |> Enum.map(&{&1, paeth_predictor(left, up, &1)})
      |> Enum.min_by(fn {_value, score} -> score end, fn -> {left, 0} end)
      |> elem(0)

    value = rem(current + predictor, 256)
    unfilter_paeth_row(rest, prev, acc <> <<value>>, row_bytes, index + 1)
  end

  defp paeth_predictor(a, b, c) do
    p = a + b - c
    pa = abs(p - a)
    pb = abs(p - b)
    pc = abs(p - c)

    cond do
      pa <= pb and pa <= pc -> a
      pb <= pc -> b
      true -> c
    end
  end

  defp add_bytes(<<a, rest_a::binary>>, <<b, rest_b::binary>>) do
    <<rem(a + b, 256)>> <> add_bytes(rest_a, rest_b)
  end

  defp add_bytes(<<>>, <<>>), do: <<>>

  @spec resize_rgba(binary(), pos_integer(), pos_integer(), pos_integer(), pos_integer()) ::
          {:ok, binary()} | {:error, term()}
  defp resize_rgba(rgba, src_w, src_h, dst_w, dst_h) do
    if byte_size(rgba) < src_w * src_h * 4 do
      {:error, :invalid_rgba_buffer}
    else
      resized =
        for y <- 0..(dst_h - 1), x <- 0..(dst_w - 1), into: <<>> do
          src_x = min(src_w - 1, div(x * src_w, dst_w))
          src_y = min(src_h - 1, div(y * src_h, dst_h))
          offset = (src_y * src_w + src_x) * 4
          :binary.part(rgba, offset, 4)
        end

      {:ok, resized}
    end
  end

  @doc false
  @spec encode_rgba(binary(), pos_integer(), pos_integer()) :: {:ok, binary()} | {:error, term()}
  def encode_rgba(rgba, width, height) do
    expected = width * height * 4

    if byte_size(rgba) < expected do
      {:error, :invalid_rgba_buffer}
    else
      pixels = :binary.part(rgba, 0, expected)

      raw =
        for y <- 0..(height - 1), into: <<>> do
          row = :binary.part(pixels, y * width * 4, width * 4)
          <<0>> <> row
        end
        |> IO.iodata_to_binary()
        |> :zlib.compress()

      ihdr =
        <<
          width::unsigned-big-32,
          height::unsigned-big-32,
          8,
          6,
          0,
          0,
          0
        >>

      {:ok,
       IO.iodata_to_binary([
         @signature,
         png_chunk("IHDR", ihdr),
         png_chunk("IDAT", raw),
         png_chunk("IEND", <<>>)
       ])}
    end
  end

  defp png_chunk(type, data) do
    crc = :erlang.crc32(type <> data)

    <<
      byte_size(data)::unsigned-big-32,
      type::binary,
      data::binary,
      crc::unsigned-big-32
    >>
  end
end
