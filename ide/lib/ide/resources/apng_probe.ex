defmodule Ide.Resources.ApngProbe do
  @moduledoc false

  @png_signature <<137, 80, 78, 71, 13, 10, 26, 10>>

  @apng8_color_type 3
  @apng8_bit_depth 8

  @type probe_result :: %{
          width: pos_integer(),
          height: pos_integer(),
          frame_count: pos_integer(),
          duration_ms: pos_integer(),
          play_count: non_neg_integer() | :infinite,
          frame_durations: [pos_integer()]
        }

  @type parse_acc :: %{
          width: pos_integer() | nil,
          height: pos_integer() | nil,
          bit_depth: pos_integer() | nil,
          color_type: pos_integer() | nil,
          frame_count: pos_integer(),
          duration_ms: pos_integer(),
          play_count: non_neg_integer() | :infinite,
          frame_durations: [pos_integer()],
          fctl_count: non_neg_integer()
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
         {:ok, parsed} <- parse_chunks(bytes),
         :ok <- validate_watch_apng(parsed) do
      {:ok, public_probe_result(parsed)}
    end
  end

  @spec validate_watch_apng(parse_acc() | probe_result()) :: :ok | {:error, atom()}
  def validate_watch_apng(parsed) when is_map(parsed) do
    cond do
      parsed.frame_count <= 1 ->
        {:error, :not_animated}

      parsed.color_type != @apng8_color_type or parsed.bit_depth != @apng8_bit_depth ->
        {:error, :requires_apng8}

      parsed.fctl_count < parsed.frame_count - 1 ->
        {:error, :malformed_apng}

      true ->
        :ok
    end
  end

  defp validate_png_signature(<<@png_signature, _::binary>>), do: :ok
  defp validate_png_signature(_), do: {:error, :invalid_png}

  defp parse_chunks(bytes) do
    <<@png_signature, rest::binary>> = bytes

    parse_chunk_loop(rest, %{
      width: nil,
      height: nil,
      bit_depth: nil,
      color_type: nil,
      frame_count: 1,
      duration_ms: 0,
      play_count: 0,
      frame_durations: [],
      fctl_count: 0
    })
  end

  defp parse_chunk_loop(<<>>, %{width: w, height: h, bit_depth: bd, color_type: ct} = acc)
       when is_integer(w) and is_integer(h) and w > 0 and h > 0 and is_integer(bd) and
              is_integer(ct) do
    {:ok, acc}
  end

  defp parse_chunk_loop(<<>>, _acc), do: {:error, :invalid_png}

  defp parse_chunk_loop(
         <<length::32-big, type::4-binary, data::binary-size(length), _crc::32, rest::binary>>,
         acc
       ) do
    acc =
      case type do
        "IHDR" ->
          <<width::32-big, height::32-big, bit_depth, color_type, _::binary>> = data
          %{acc | width: width, height: height, bit_depth: bit_depth, color_type: color_type}

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
          <<_seq::32, _w::32, _h::32, _x::32, _y::32, delay_num::16, delay_den::16,
            _rest::binary>> = data

          denom = max(delay_den, 1)
          frame_ms = max(div(delay_num * 1000, denom), 1)

          %{
            acc
            | duration_ms: acc.duration_ms + frame_ms,
              frame_durations: acc.frame_durations ++ [frame_ms],
              fctl_count: acc.fctl_count + 1
          }

        _ ->
          acc
      end

    parse_chunk_loop(rest, acc)
  end

  defp parse_chunk_loop(_rest, _acc), do: {:error, :invalid_png}

  defp public_probe_result(parsed) do
    %{
      width: parsed.width,
      height: parsed.height,
      frame_count: parsed.frame_count,
      duration_ms: parsed.duration_ms,
      play_count: parsed.play_count,
      frame_durations: parsed.frame_durations
    }
  end
end
