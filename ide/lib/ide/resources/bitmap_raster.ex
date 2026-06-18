defmodule Ide.Resources.BitmapRaster do
  @moduledoc """
  Detects raster image formats and normalizes bitmap imports to PNG for Pebble packaging.
  """

  alias Ide.Resources.{BitmapMonochrome, PngInfo}

  @png_signature <<137, 80, 78, 71, 13, 10, 26, 10>>
  @jpeg_signature <<0xFF, 0xD8, 0xFF>>
  @supported_exts ~w(.png .bmp .jpg .jpeg .webp .gif)

  @type format :: :png | :jpeg | :bmp | :gif | :webp | :unknown

  @type prepared :: %{
          bytes: binary(),
          mime: String.t(),
          width: non_neg_integer(),
          height: non_neg_integer(),
          safe_name: String.t(),
          converted: boolean()
        }

  @spec normalize_for_import(binary(), String.t()) ::
          {:ok, prepared()} | {:error, atom()}
  def normalize_for_import(bytes, original_name)
      when is_binary(bytes) and is_binary(original_name) do
    with {:ok, safe_name, _declared_mime} <- filename_and_mime(original_name),
         {:ok, normalized} <- normalize_bytes(bytes) do
      {:ok,
       normalized
       |> Map.put(:safe_name, safe_name)
       |> Map.put(:mime, "image/png")}
    end
  end

  @spec detect_format(binary()) :: format()
  def detect_format(bytes) when is_binary(bytes) do
    cond do
      jpeg?(bytes) -> :jpeg
      png?(bytes) -> :png
      bmp?(bytes) -> :bmp
      gif?(bytes) -> :gif
      webp?(bytes) -> :webp
      true -> :unknown
    end
  end

  @spec normalize_bytes(binary()) ::
          {:ok, %{bytes: binary(), width: non_neg_integer(), height: non_neg_integer(), converted: boolean()}}
          | {:error, atom()}
  def normalize_bytes(bytes) when is_binary(bytes) do
    case detect_format(bytes) do
      :png ->
        case PngInfo.ihdr(bytes) do
          {:ok, %{width: width, height: height}} ->
            {:ok, %{bytes: bytes, width: width, height: height, converted: false}}

          {:error, :invalid_png} ->
            case convert_bytes(bytes) do
              {:ok, result} ->
                {:ok, result}

              {:error, :bitmap_converter_missing} ->
                {:error, :bitmap_converter_missing}

              {:error, _} ->
                {:error, :invalid_bitmap_image}
            end
        end

      format when format in [:jpeg, :bmp, :gif, :webp] ->
        convert_bytes(bytes)

      :unknown ->
        {:error, :invalid_bitmap_image}
    end
  end

  @spec filename_and_mime(String.t()) :: {:ok, String.t(), String.t()} | {:error, :unsupported_bitmap_type}
  def filename_and_mime(original_name) when is_binary(original_name) do
    ext =
      original_name
      |> Path.extname()
      |> String.downcase()

    if ext in @supported_exts do
      base =
        original_name
        |> Path.basename()
        |> Path.rootname()
        |> String.replace(~r/[^A-Za-z0-9_-]+/, "_")
        |> String.trim("_")
        |> case do
          "" -> "bitmap"
          value -> value
        end

      {:ok, String.downcase(base) <> ext, mime_for_ext(ext)}
    else
      {:error, :unsupported_bitmap_type}
    end
  end

  defp mime_for_ext(".png"), do: "image/png"
  defp mime_for_ext(".bmp"), do: "image/bmp"
  defp mime_for_ext(".jpg"), do: "image/jpeg"
  defp mime_for_ext(".jpeg"), do: "image/jpeg"
  defp mime_for_ext(".gif"), do: "image/gif"
  defp mime_for_ext(".webp"), do: "image/webp"

  defp png?(<<@png_signature, _::binary>>), do: true
  defp png?(_), do: false

  defp jpeg?(<<@jpeg_signature, _::binary>>), do: true
  defp jpeg?(_), do: false

  defp bmp?(<<"BM", _::binary>>), do: true
  defp bmp?(_), do: false

  defp gif?(<<"GIF87a", _::binary>>), do: true
  defp gif?(<<"GIF89a", _::binary>>), do: true
  defp gif?(_), do: false

  defp webp?(<<"RIFF", _size::32-little, "WEBP", _::binary>>), do: true
  defp webp?(_), do: false

  defp convert_bytes(bytes) do
    case BitmapMonochrome.imagemagick_bin() do
      nil ->
        {:error, :bitmap_converter_missing}

      bin ->
        input =
          System.tmp_dir!()
          |> Path.join("bitmap_import_in_#{System.unique_integer([:positive])}")

        output =
          System.tmp_dir!()
          |> Path.join("bitmap_import_out_#{System.unique_integer([:positive])}.png")

        try do
          with :ok <- File.write(input, bytes),
               :ok <- convert_with_bin(bin, input, output),
               {:ok, png_bytes} <- File.read(output),
               {:ok, %{width: width, height: height}} <- PngInfo.ihdr(png_bytes) do
            {:ok, %{bytes: png_bytes, width: width, height: height, converted: true}}
          else
            {:error, :invalid_png} -> {:error, :bitmap_conversion_failed}
            _ -> {:error, :bitmap_conversion_failed}
          end
        after
          File.rm(input)
          File.rm(output)
        end
    end
  end

  defp convert_with_bin(bin, input_path, output_path) do
    input_path = Path.expand(input_path)
    output_path = Path.expand(output_path)
    File.mkdir_p!(Path.dirname(output_path))

    args =
      if String.ends_with?(Path.basename(bin), "magick") do
        [input_path, "PNG:" <> output_path]
      else
        [input_path, output_path]
      end

    {_output, exit_status} = System.cmd(bin, args, stderr_to_stdout: true)

    if exit_status == 0 and File.exists?(output_path) do
      :ok
    else
      File.rm(output_path)
      {:error, :bitmap_conversion_failed}
    end
  end
end
