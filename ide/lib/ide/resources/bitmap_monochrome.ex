defmodule Ide.Resources.BitmapMonochrome do
  @moduledoc """
  Converts color PNG assets to 1-bit monochrome PNGs for Pebble `~bw` variants.

  Uses ImageMagick (`magick` or `convert`) when available on the IDE host.
  """

  @spec convert(String.t(), String.t()) ::
          :ok | {:error, :converter_missing | :conversion_failed}
  def convert(input_path, output_path)
      when is_binary(input_path) and is_binary(output_path) do
    case imagemagick_bin() do
      nil -> {:error, :converter_missing}
      bin -> convert_with_bin(bin, input_path, output_path)
    end
  end

  @spec convert_bytes(binary()) :: {:ok, binary()} | {:error, :converter_missing | :conversion_failed}
  def convert_bytes(bytes) when is_binary(bytes) do
    input = System.tmp_dir!() |> Path.join("bitmap_color_#{System.unique_integer([:positive])}.png")
    output = System.tmp_dir!() |> Path.join("bitmap_bw_#{System.unique_integer([:positive])}.png")

    try do
      with :ok <- File.write(input, bytes),
           :ok <- convert(input, output),
           {:ok, bw_bytes} <- File.read(output) do
        {:ok, bw_bytes}
      end
    after
      File.rm(input)
      File.rm(output)
    end
  end

  @spec imagemagick_bin() :: String.t() | nil
  def imagemagick_bin do
    [
      System.get_env("IMAGEMAGICK_BIN"),
      System.get_env("MAGICK_BIN"),
      System.find_executable("magick"),
      System.find_executable("convert")
    ]
    |> Enum.find(&executable_file?/1)
  end

  defp executable_file?(path) when is_binary(path) and path != "" do
    File.regular?(path) and File.exists?(path)
  end

  defp executable_file?(_), do: false

  defp convert_with_bin(bin, input_path, output_path) do
    input_path = Path.expand(input_path)
    output_path = Path.expand(output_path)
    File.mkdir_p!(Path.dirname(output_path))

    args =
      if String.ends_with?(Path.basename(bin), "magick") do
        [input_path, "-background", "white", "-alpha", "remove", "-alpha", "off", "-colorspace",
         "Gray", "-monochrome", "PNG:" <> output_path]
      else
        [
          input_path,
          "-background",
          "white",
          "-alpha",
          "remove",
          "-alpha",
          "off",
          "-colorspace",
          "Gray",
          "-monochrome",
          output_path
        ]
      end

    {_output, exit_status} = System.cmd(bin, args, stderr_to_stdout: true)

    if exit_status == 0 and File.exists?(output_path) do
      :ok
    else
      File.rm(output_path)
      {:error, :conversion_failed}
    end
  end
end
