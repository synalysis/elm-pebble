defmodule Mix.Tasks.Ide.SizeReport do
  @moduledoc """
  Reports repeatable compiler and optional Pebble package sizes for IDE templates.

      mix ide.size_report
      mix ide.size_report --package
      mix ide.size_report --templates watchface-yes,game-2048,starter
      mix ide.size_report --package --targets flint,gabbro
  """

  use Mix.Task

  alias Ide.PebbleToolchain
  alias Ide.ProjectTemplates

  @shortdoc "Reports compiler and Pebble package sizes for templates"
  @default_templates ["watchface-yes", "game-2048", "starter"]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, invalid} =
      OptionParser.parse(args,
        strict: [package: :boolean, templates: :string, out: :string, targets: :string],
        aliases: [p: :package]
      )

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    out_root =
      opts
      |> Keyword.get(:out, Path.expand("tmp/size_report", File.cwd!()))
      |> Path.expand()

    templates = parse_templates(Keyword.get(opts, :templates))
    package? = Keyword.get(opts, :package, false)
    targets = parse_targets(Keyword.get(opts, :targets))

    reports =
      Enum.map(templates, fn template ->
        template
        |> report_template(out_root, package?, targets)
        |> case do
          {:ok, report} -> report
          {:error, reason} -> %{template: template, status: "error", reason: inspect(reason)}
        end
      end)

    IO.puts(Jason.encode!(%{templates: reports}, pretty: true))
  end

  defp parse_templates(nil), do: @default_templates

  defp parse_templates(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_targets(nil), do: ["flint", "gabbro"]
  defp parse_targets("all"), do: :all

  defp parse_targets(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp report_template(template, out_root, package?, targets) do
    workspace_root = Path.join(out_root, template)
    compile_out = Path.join(workspace_root, ".size/elmc")

    with :ok <- reset_workspace(template, workspace_root),
         :ok <-
           Elmc.compile(Path.join(workspace_root, "watch"), %{
             out_dir: compile_out,
             entry_module: "Main",
             prune_runtime: true
           })
           |> normalize_compile_result() do
      package_report =
        if package? do
          package_template(template, workspace_root, targets)
        else
          %{status: "skipped"}
        end

      {:ok,
       %{
         template: template,
         status: "ok",
         compiler: compiler_report(compile_out),
         package: package_report
       }}
    end
  end

  defp reset_workspace(template, workspace_root) do
    _ = File.rm_rf(workspace_root)

    with :ok <- File.mkdir_p(workspace_root) do
      ProjectTemplates.apply_template(template, workspace_root)
    end
  end

  defp normalize_compile_result({:ok, _result}), do: :ok
  defp normalize_compile_result({:error, reason}), do: {:error, reason}

  defp compiler_report(out_dir) do
    generated_c = Path.join(out_dir, "c/elmc_generated.c")
    pebble_c = Path.join(out_dir, "c/elmc_pebble.c")
    runtime_dir = Path.join(out_dir, "runtime")

    %{
      generated_c: file_report(generated_c),
      pebble_c: file_report(pebble_c),
      runtime_bytes:
        runtime_dir |> Path.join("**/*") |> Path.wildcard() |> total_regular_file_size()
    }
  end

  defp package_template(template, workspace_root, targets) do
    target_type = ProjectTemplates.target_type_for_template(template)

    targets
    |> normalize_package_targets()
    |> Enum.map(fn target ->
      opts = [
        workspace_root: workspace_root,
        target_type: target_type,
        project_name: template
      ]

      opts =
        if target == :all do
          opts
        else
          Keyword.put(opts, :target_platforms, [target])
        end

      case PebbleToolchain.package(template, opts) do
        {:ok, result} ->
          build_dir = Path.join(result.app_root, "build")

          %{
            target: target_name(target),
            status: "ok",
            artifact: file_report(result.artifact_path),
            app_bins: target_bin_reports(build_dir, target),
            objects: object_reports(build_dir),
            map_symbols: map_symbol_report(Path.join(build_dir, "pebble-app.map")),
            has_phone_companion: result.has_phone_companion
          }

        {:error, reason} ->
          %{target: target_name(target), status: "error", reason: inspect(reason)}
      end
    end)
  end

  defp normalize_package_targets(:all), do: [:all]
  defp normalize_package_targets([]), do: ["flint", "gabbro"]
  defp normalize_package_targets(targets), do: targets

  defp target_name(:all), do: "all"
  defp target_name(target), do: target

  defp target_bin_reports(build_dir, :all) do
    build_dir
    |> Path.join("**/pebble-app*.bin")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(&file_report/1)
  end

  defp target_bin_reports(build_dir, target) do
    target_dir = Path.join(build_dir, target)

    ["pebble-app.bin", "pebble-app.raw.bin"]
    |> Enum.map(&Path.join(target_dir, &1))
    |> Enum.map(&file_report/1)
  end

  defp object_reports(build_dir) do
    build_dir
    |> Path.join("**/*.o")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(&object_report/1)
  end

  defp object_report(path) do
    report = file_report(path)

    case arm_size(path) do
      nil -> report
      size -> Map.put(report, :size, size)
    end
  end

  defp arm_size(path) do
    with size_bin when is_binary(size_bin) <- System.find_executable("arm-none-eabi-size"),
         {output, 0} <- System.cmd(size_bin, [path]) do
      output
      |> String.split("\n", trim: true)
      |> Enum.at(1)
      |> parse_size_line()
    else
      _ -> nil
    end
  end

  defp parse_size_line(nil), do: nil

  defp parse_size_line(line) do
    case String.split(line, ~r/\s+/, trim: true) do
      [text, data, bss, dec, hex | _] ->
        %{
          text: parse_int(text),
          data: parse_int(data),
          bss: parse_int(bss),
          dec: parse_int(dec),
          hex: hex
        }

      _ ->
        nil
    end
  end

  defp map_symbol_report(path) do
    with {:ok, contents} <- File.read(path) do
      contents
      |> String.split("\n", trim: true)
      |> Enum.flat_map(&parse_map_symbol/1)
      |> Enum.sort_by(& &1.size, :desc)
      |> Enum.take(30)
    else
      _ -> []
    end
  end

  defp parse_map_symbol(line) do
    case Regex.run(~r/^\s+0x[0-9a-fA-F]+\s+0x([0-9a-fA-F]+)\s+(.+)$/, line) do
      [_, size_hex, symbol] ->
        [%{size: parse_hex(size_hex), symbol: String.trim(symbol)}]

      _ ->
        []
    end
  end

  defp file_report(path) do
    %{
      path: Path.relative_to_cwd(path),
      bytes: file_size(path),
      lines: line_count(path)
    }
  end

  defp file_size(path) do
    case File.stat(path) do
      {:ok, %{type: :regular, size: size}} -> size
      _ -> nil
    end
  end

  defp parse_int(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp parse_hex(value) do
    case Integer.parse(value, 16) do
      {int, _} -> int
      :error -> 0
    end
  end

  defp line_count(path) do
    case File.read(path) do
      {:ok, contents} -> contents |> String.split("\n", trim: false) |> length()
      _ -> nil
    end
  end

  defp total_regular_file_size(paths) do
    paths
    |> Enum.map(&file_size/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sum()
  end
end
