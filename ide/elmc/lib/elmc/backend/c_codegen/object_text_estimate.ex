defmodule Elmc.Backend.CCodegen.ObjectTextEstimate do
  @moduledoc false

  @pebble_c_flags ~w(-c -mcpu=cortex-m4 -mthumb -Os -ffunction-sections -fdata-sections)

  alias Elmc.Types, as: RootTypes

  @type source_row :: RootTypes.object_text_source_row()

  @type estimate_unavailable :: RootTypes.object_text_estimate_unavailable()
  @type estimate_available :: RootTypes.object_text_estimate_available()
  @type t :: RootTypes.object_text_estimate()

  @spec estimate(String.t(), keyword()) :: t()
  def estimate(out_dir, opts \\ []) when is_binary(out_dir) do
    gcc = gcc_bin()
    size_bin = size_bin()

    if is_binary(gcc) and is_binary(size_bin) do
      do_estimate(out_dir, gcc, size_bin, opts)
    else
      %{
        "available" => false,
        "reason" => "arm-none-eabi-gcc or arm-none-eabi-size not found"
      }
    end
  end

  @spec elmc_stack_text(t()) :: non_neg_integer() | nil
  def elmc_stack_text(%{"available" => true} = estimate) do
    Map.get(estimate, "elmc_app_text") || Map.get(estimate, "elmc_stack_text")
  end

  def elmc_stack_text(_), do: nil

  defp do_estimate(out_dir, gcc, size_bin, opts) do
    includes = include_flags(opts)
    tmp_root = Path.join(System.tmp_dir!(), "elmc_object_text_#{System.unique_integer()}")

    try do
      sources = list_sources(out_dir)

      if sources == [] do
        %{"available" => false, "reason" => "no C sources under #{out_dir}"}
      else
        {rows, total} =
          Enum.map_reduce(sources, 0, fn source, acc ->
            object = Path.join(tmp_root, object_name(source, out_dir))

            case compile_object(gcc, includes, source, object) do
              :ok ->
                text = object_text(size_bin, object)
                row = %{"source" => Path.relative_to(source, out_dir), "text" => text}
                {row, acc + text}

              {:error, reason} ->
                row = %{"source" => Path.relative_to(source, out_dir), "error" => reason}
                {row, acc}
            end
          end)

        generated_text =
          rows
          |> Enum.find(fn row -> row["source"] == "c/elmc_generated.c" end)
          |> case do
            %{"text" => text} -> text
            _ -> nil
          end

        %{
          "available" => true,
          "elmc_app_text" => total,
          "elmc_stack_text" => total,
          "generated_text" => generated_text,
          "sources" => rows
        }
      end
    after
      File.rm_rf(tmp_root)
    end
  end

  defp list_sources(out_dir) do
    out_dir
    |> app_source_paths()
    |> Enum.filter(&File.regular?/1)
  end

  defp app_source_paths(out_dir) do
    [
      Path.join(out_dir, "c/elmc_generated.c"),
      Path.join(out_dir, "c/elmc_pebble.c"),
      Path.join(out_dir, "c/elmc_worker.c"),
      Path.join(out_dir, "c/elmc_ports.c")
    ]
  end

  defp object_name(source, out_dir) do
    source
    |> Path.relative_to(out_dir)
    |> String.replace("/", "__")
    |> Kernel.<>(".o")
  end

  defp compile_object(gcc, includes, source, object) do
    File.mkdir_p!(Path.dirname(object))

    case System.cmd(gcc, @pebble_c_flags ++ includes ++ [source, "-o", object], stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, _} -> {:error, String.trim(output) |> String.slice(0, 200)}
    end
  end

  defp object_text(size_bin, object) do
    case System.cmd(size_bin, [object], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> List.last()
        |> parse_text_column()

      _ ->
        0
    end
  end

  defp parse_text_column(line) when is_binary(line) do
    case String.split(line, ~r/\s+/, trim: true) do
      [text | _] -> String.to_integer(text)
      _ -> 0
    end
  end

  defp parse_text_column(_), do: 0

  defp include_flags(opts) do
    sdk_root = Keyword.get(opts, :sdk_root, sdk_core_root())
    elmc_include = Path.expand("../../../../c/include", __DIR__)

    [
      "-I#{Path.join(sdk_root, "pebble/flint/include")}",
      "-I#{Path.join(sdk_root, "pebble/common/include")}",
      "-I#{elmc_include}"
    ]
  end

  defp sdk_core_root do
    Path.expand("~/.pebble-sdk/SDKs/current/sdk-core")
  end

  defp gcc_bin do
    find_tool("arm-none-eabi-gcc")
  end

  defp size_bin do
    find_tool("arm-none-eabi-size")
  end

  defp find_tool(name) do
    sdk_candidates = [
      Path.expand("~/.pebble-sdk/SDKs/current/toolchain/arm-none-eabi/bin/#{name}"),
      Path.expand("~/.pebble-sdk/SDKs/4.9.169/toolchain/arm-none-eabi/bin/#{name}")
    ]

    ([System.find_executable(name)] ++ sdk_candidates)
    |> Enum.reject(&is_nil/1)
    |> Enum.find(&File.regular?/1)
  end
end
