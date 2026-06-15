defmodule Ide.Resources.ApngStaticPreview do
  @moduledoc """
  Builds a single-frame PNG from watch APNG assets for static browser previews.
  """

  import Bitwise

  alias Ide.Resources.ApngProbe

  @png_signature <<137, 80, 78, 71, 13, 10, 26, 10>>

  @drop_chunk_types ~w(acTL fcTL fdAT)

  @spec static_png_bytes(binary()) :: {:ok, binary()} | {:error, atom()}
  def static_png_bytes(bytes) when is_binary(bytes) do
    case ApngProbe.probe_bytes(bytes) do
      {:ok, %{frame_count: frame_count}} when frame_count > 1 ->
        strip_animation(bytes)

      {:ok, _} ->
        {:ok, bytes}

      {:error, :not_animated} ->
        {:ok, bytes}

      {:error, _} = error ->
        error
    end
  end

  @spec strip_animation(binary()) :: {:ok, binary()} | {:error, atom()}
  defp strip_animation(bytes) do
    with :ok <- validate_signature(bytes),
         {:ok, chunks} <- parse_chunks(bytes),
         {:ok, kept} <- first_frame_chunks(chunks) do
      {:ok, encode_png(kept)}
    end
  end

  defp validate_signature(<<@png_signature, _::binary>>), do: :ok
  defp validate_signature(_), do: {:error, :invalid_png}

  @spec parse_chunks(binary()) :: {:ok, [{String.t(), binary()}]} | {:error, atom()}
  defp parse_chunks(bytes) do
    <<@png_signature, rest::binary>> = bytes
    parse_chunk_loop(rest, [])
  end

  defp parse_chunk_loop(<<>>, acc), do: {:ok, Enum.reverse(acc)}

  defp parse_chunk_loop(
         <<length::32-big, type::4-binary, data::binary-size(length), _crc::32, rest::binary>>,
         acc
       ) do
    parse_chunk_loop(rest, [{type, data} | acc])
  end

  defp parse_chunk_loop(_rest, _acc), do: {:error, :invalid_png}

  @spec first_frame_chunks([{String.t(), binary()}]) :: {:ok, [{String.t(), binary()}]}
  defp first_frame_chunks(chunks) do
    kept =
      chunks
      |> Enum.reduce_while([], fn {type, _data} = chunk, acc ->
        cond do
          type in @drop_chunk_types ->
            {:cont, acc}

          type == "IDAT" ->
            {:halt, Enum.reverse([chunk | acc])}

          true ->
            {:cont, [chunk | acc]}
        end
      end)

    case kept do
      [] ->
        {:error, :malformed_apng}

      chunks ->
        {:ok, chunks ++ [{"IEND", ""}]}
    end
  end

  @spec encode_png([{String.t(), binary()}]) :: binary()
  defp encode_png(chunks) do
    body =
      Enum.map_join(chunks, "", fn {type, data} ->
        encode_chunk(type, data)
      end)

    @png_signature <> body
  end

  @spec encode_chunk(String.t(), binary()) :: binary()
  defp encode_chunk(type, data) when byte_size(type) == 4 and is_binary(data) do
    crc = :erlang.crc32([type, data]) &&& 0xFFFFFFFF
    <<byte_size(data)::32-big, type::binary, data::binary, crc::32-big>>
  end
end
