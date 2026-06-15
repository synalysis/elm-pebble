defmodule Ide.Resources.PngInfo do
  @moduledoc false

  @png_signature <<137, 80, 78, 71, 13, 10, 26, 10>>

  @type ihdr :: %{
          width: pos_integer(),
          height: pos_integer(),
          bit_depth: pos_integer(),
          color_type: pos_integer()
        }

  @spec color_palette_image?(binary()) :: boolean()
  def color_palette_image?(bytes) when is_binary(bytes) do
    case ihdr(bytes) do
      {:ok, %{color_type: 2}} -> true
      {:ok, %{color_type: 4}} -> true
      {:ok, %{color_type: 6}} -> true
      {:ok, %{color_type: 3, bit_depth: bit_depth}} when bit_depth > 1 -> true
      _ -> false
    end
  end

  def color_palette_image?(_), do: false

  @spec ihdr(binary()) :: {:ok, ihdr()} | {:error, :invalid_png}
  def ihdr(bytes) when is_binary(bytes) do
    with :ok <- validate_signature(bytes),
         {:ok, data} <- first_chunk_data(bytes, "IHDR"),
         <<width::32-big, height::32-big, bit_depth, color_type, _::binary>> <- data,
         true <- width > 0 and height > 0 do
      {:ok, %{width: width, height: height, bit_depth: bit_depth, color_type: color_type}}
    else
      _ -> {:error, :invalid_png}
    end
  end

  defp validate_signature(<<@png_signature, _::binary>>), do: :ok
  defp validate_signature(_), do: {:error, :invalid_png}

  defp first_chunk_data(bytes, type) when is_binary(type) and byte_size(type) == 4 do
    <<@png_signature, rest::binary>> = bytes

    case chunk_data(rest, type) do
      {:ok, data} -> {:ok, data}
      :error -> {:error, :invalid_png}
    end
  rescue
    MatchError -> {:error, :invalid_png}
  end

  defp chunk_data(<<length::32-big, chunk_type::4-binary, data::binary-size(length), _crc::32, rest::binary>>, type) do
    if chunk_type == type, do: {:ok, data}, else: chunk_data(rest, type)
  end

  defp chunk_data(_rest, _type), do: :error
end
