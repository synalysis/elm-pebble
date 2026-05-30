defmodule Ide.Resources.GifToApng do
  @moduledoc false

  alias Ide.Paths

  @spec gif2apng_bin() :: String.t() | nil
  def gif2apng_bin do
    [
      System.get_env("GIF2APNG_BIN"),
      Paths.priv_path("bin/gif2apng"),
      System.find_executable("gif2apng")
    ]
    |> Enum.find(&executable_file?/1)
  end

  @spec convert(String.t(), String.t()) :: :ok | {:error, :converter_missing | :conversion_failed}
  def convert(input_path, output_path)
      when is_binary(input_path) and is_binary(output_path) do
    case gif2apng_bin() do
      nil ->
        {:error, :converter_missing}

      bin ->
        convert_with_bin(bin, input_path, output_path)
    end
  end

  def convert(_, _), do: {:error, :conversion_failed}

  defp executable_file?(path) when is_binary(path) and path != "" do
    File.regular?(path) and File.exists?(path)
  end

  defp executable_file?(_), do: false

  # gif2apng 1.9: no -o flag; pass `gif2apng -z0 input.gif output.png`.
  # It only opens relative input paths, so run with cwd = input directory.
  defp convert_with_bin(bin, input_path, output_path) do
    input_dir = Path.dirname(Path.expand(input_path))
    input_name = Path.basename(input_path)
    tmp_name = "gif2apng_#{System.unique_integer([:positive])}.png"
    tmp_path = Path.join(input_dir, tmp_name)
    output_path = Path.expand(output_path)

    with :ok <- File.mkdir_p(input_dir),
         :ok <- File.mkdir_p(Path.dirname(output_path)) do
      {_output, exit_status} =
        System.cmd(bin, ["-z0", input_name, tmp_name], cd: input_dir, stderr_to_stdout: true)

      produced =
        cond do
          File.exists?(tmp_path) -> tmp_path
          true -> Path.join(input_dir, Path.rootname(input_name) <> ".png")
        end

      cond do
        exit_status == 0 and File.exists?(produced) ->
          move_into_place(produced, output_path)

        true ->
          File.rm(tmp_path)
          {:error, :conversion_failed}
      end
    end
  end

  defp move_into_place(from, to) do
    from = Path.expand(from)
    to = Path.expand(to)

    cond do
      from == to ->
        :ok

      true ->
        File.mkdir_p!(Path.dirname(to))

        case File.rename(from, to) do
          :ok -> :ok
          {:error, :exdev} -> copy_and_remove(from, to)
          {:error, _} -> copy_and_remove(from, to)
        end
    end
  end

  defp copy_and_remove(from, to) do
    with {:ok, bytes} <- File.read(from),
         :ok <- File.write(to, bytes),
         :ok <- File.rm(from) do
      :ok
    end
  end
end
