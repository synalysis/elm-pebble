defmodule Ide.Resources.ApngProbe do
  @moduledoc false

  @png_signature <<137, 80, 78, 71, 13, 10, 26, 10>>

  @type probe_result :: %{
          width: pos_integer(),
          height: pos_integer(),
          frame_count: pos_integer(),
          duration_ms: pos_integer(),
          play_count: non_neg_integer() | :infinite,
          frame_durations: [pos_integer()]
        }

  @spec probe(String.t()) :: {:ok, probe_result()} | {:error, atom()}
  def probe(path) when is_binary(path) do
    with {:ok, bytes} <- File.read(path) do
      probe_bytes(bytes)
    end
  end

  @spec probe_bytes(binary()) :: {:ok, probe_result()} | {:error, atom()}
  def probe_bytes(bytes) when is_binary(bytes) do
    with :ok <- validate_png_signature(bytes),
         {:ok, result} <- parse_chunks(bytes) do
      if result.frame_count > 1 do
        {:ok, result}
      else
        {:error, :not_animated}
      end
    end
  end

  defp validate_png_signature(<<@png_signature, _::binary>>), do: :ok
  defp validate_png_signature(_), do: {:error, :invalid_png}

  defp parse_chunks(bytes) do
    <<@png_signature, rest::binary>> = bytes
    parse_chunk_loop(rest, %{
      width: nil,
      height: nil,
      frame_count: 1,
      duration_ms: 0,
      play_count: 0,
      frame_durations: []
    })
  end

  defp parse_chunk_loop(<<>>, %{width: w, height: h} = acc) when is_integer(w) and is_integer(h) and w > 0 and h > 0 do
    {:ok, acc}
  end

  defp parse_chunk_loop(<<>>, _acc), do: {:error, :invalid_png}

  defp parse_chunk_loop(<<length::32-big, type::4-binary, data::binary-size(length), _crc::32, rest::binary>>, acc) do
    acc =
      case type do
        "IHDR" ->
          <<width::32-big, height::32-big, _::binary>> = data
          %{acc | width: width, height: height}

        "acTL" ->
          <<num_frames::32-big, num_plays::32-big>> = data

          play_count =
            if num_plays == 0 do
              :infinite
            else
              num_plays
            end

          %{acc | frame_count: num_frames, play_count: play_count}

        "fcTL" ->
          <<_seq::32, _w::32, _h::32, _x::32, _y::32, delay_num::16, delay_den::16, _rest::binary>> = data
          denom = max(delay_den, 1)
          frame_ms = max(div(delay_num * 1000, denom), 1)
          %{acc | duration_ms: acc.duration_ms + frame_ms, frame_durations: acc.frame_durations ++ [frame_ms]}

        _ ->
          acc
      end

    parse_chunk_loop(rest, acc)
  end

  defp parse_chunk_loop(_rest, _acc), do: {:error, :invalid_png}
end
