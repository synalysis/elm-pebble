defmodule Ide.ElmFormat do
  @moduledoc false

  @formatter "elm-format"
  @elm_version_args ["--yes", "--elm-version", "0.19"]

  @spec format(String.t(), keyword()) :: {:ok, map()} | {:error, map()}
  def format(source, opts \\ []) when is_binary(source) do
    cwd = Keyword.get(opts, :cwd, File.cwd!())

    case run_elm_format(source, cwd) do
      {:ok, formatted} ->
        {:ok,
         %{
           formatted_source: formatted,
           changed?: formatted != source,
           diagnostics: [],
           formatter: "elm-format",
           details: %{
             backend: :elm_format,
             command: "#{@formatter} --output <file> --elm-version 0.19"
           }
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec run_elm_format(String.t(), String.t()) :: {:ok, String.t()} | {:error, map()}
  defp run_elm_format(source, cwd) do
    input_path = temp_path(".elm")
    output_path = temp_path(".elm")

    try do
      with :ok <- File.write(input_path, source),
           {:ok, formatted} <- run_elm_format_file(input_path, output_path, cwd) do
        {:ok, formatted}
      else
        {:error, %{source: "elm-format"} = reason} ->
          {:error, reason}

        {:error, reason} ->
          {:error,
           %{
             severity: "error",
             source: "elm-format",
             message: "Could not prepare formatter input: #{inspect(reason)}",
             line: nil,
             column: nil
           }}
      end
    after
      cleanup_temp(input_path)
      cleanup_temp(output_path)
    end
  end

  @spec run_elm_format_file(String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, map()}
  defp run_elm_format_file(input_path, output_path, cwd) do
    args = [input_path, "--output", output_path | @elm_version_args]

    case System.cmd(@formatter, args, cd: cwd, stderr_to_stdout: true) do
      {_output, 0} ->
        case File.read(output_path) do
          {:ok, formatted} ->
            {:ok, formatted}

          {:error, reason} ->
            {:error,
             %{
               severity: "error",
               source: "elm-format",
               message: "Could not read formatter output: #{inspect(reason)}",
               line: nil,
               column: nil
             }}
        end

      {output, status} ->
        {:error,
         %{
           severity: "error",
           source: "elm-format",
           message: String.trim(output),
           line: nil,
           column: nil,
           exit_status: status
         }}
    end
  rescue
    error ->
      {:error,
       %{
         severity: "error",
         source: "elm-format",
         message: Exception.message(error),
         line: nil,
         column: nil
       }}
  end

  @spec temp_path(String.t()) :: String.t()
  defp temp_path(ext) do
    suffix = System.unique_integer([:positive, :monotonic])
    Path.join(System.tmp_dir!(), "elm-pebble-format-#{suffix}#{ext}")
  end

  @spec cleanup_temp(String.t()) :: :ok
  defp cleanup_temp(path) when is_binary(path) do
    _ = File.rm(path)
    :ok
  end
end
