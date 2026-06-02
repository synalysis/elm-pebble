defmodule Mix.Tasks.Ide.SizeReport do
  @moduledoc """
  Reports repeatable compiler and optional Pebble package sizes for IDE templates.

      mix ide.size_report
      mix ide.size_report --package
      mix ide.size_report --templates watchface-yes,game-2048,starter
      mix ide.size_report --package --targets flint,gabbro
      mix ide.size_report --package --baseline tmp/map_size_report --fail-on-regression
      mix ide.size_report --baseline-manifest priv/size_report_baselines/flint.json --fail-on-regression
  """

  use Mix.Task

  alias Ide.PebbleToolchain
  alias Ide.ProjectTemplates

  @shortdoc "Reports compiler and Pebble package sizes for templates"
  @default_templates ["watchface-yes", "watchface-tangram-time", "game-2048", "starter"]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, invalid} =
      OptionParser.parse(args,
        strict: [
          package: :boolean,
          templates: :string,
          out: :string,
          targets: :string,
          baseline: :string,
          baseline_manifest: :string,
          fail_on_regression: :boolean,
          max_bin_regression: :integer,
          max_generated_c_regression: :integer
        ],
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
    baseline_root = baseline_root(opts)
    baseline_manifest = load_baseline_manifest(opts)
    max_bin_regression = Keyword.get(opts, :max_bin_regression, 512)
    max_generated_c_regression = Keyword.get(opts, :max_generated_c_regression, 8192)
    fail_on_regression? = Keyword.get(opts, :fail_on_regression, false)

    reports =
      Enum.map(templates, fn template ->
        template
        |> report_template(out_root, package?, targets)
        |> case do
          {:ok, report} -> report
          {:error, reason} -> %{template: template, status: "error", reason: inspect(reason)}
        end
      end)

    reports =
      reports
      |> maybe_apply_directory_baseline(baseline_root, out_root, targets)
      |> maybe_apply_manifest_baseline(baseline_manifest, targets)

    if fail_on_regression? and (baseline_root || baseline_manifest) do
      enforce_regression_budget!(reports, max_bin_regression, max_generated_c_regression)
    end

    IO.puts(Jason.encode!(%{templates: reports}, pretty: true))
  end

  defp baseline_root(opts) do
    case Keyword.get(opts, :baseline) do
      nil -> nil
      path -> Path.expand(path)
    end
  end

  defp load_baseline_manifest(opts) do
    case Keyword.get(opts, :baseline_manifest) do
      nil ->
        nil

      path ->
        path = Path.expand(path)

        case File.read(path) do
          {:ok, contents} ->
            contents
            |> Jason.decode!()
            |> Map.get("templates", %{})

          {:error, reason} ->
            Mix.raise("could not read baseline manifest #{path}: #{inspect(reason)}")
        end
    end
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
            map_symbols: map_symbol_report(find_pebble_map_file(build_dir)),
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

  defp find_pebble_map_file(build_dir) do
    candidates = [
      Path.join(build_dir, "pebble-app.map"),
      Path.join(build_dir, "flint/pebble-app.map"),
      Path.join(build_dir, "gabbro/pebble-app.map")
    ]

    Enum.find_value(candidates, fn path ->
      if File.regular?(path), do: path
    end) ||
      (build_dir
       |> Path.join("**/pebble-app.map")
       |> Path.wildcard()
       |> Enum.sort()
       |> List.first()) ||
      Path.join(build_dir, "pebble-app.map")
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

  defp maybe_apply_directory_baseline(reports, nil, _out_root, _targets), do: reports

  defp maybe_apply_directory_baseline(reports, baseline_root, out_root, targets) do
    Enum.map(reports, fn report ->
      Map.put(report, :baseline, directory_baseline_compare(report, baseline_root, out_root, targets))
    end)
  end

  defp maybe_apply_manifest_baseline(reports, nil, _targets), do: reports

  defp maybe_apply_manifest_baseline(reports, manifest, targets) do
    target = baseline_compare_target(targets)
    bin_key = "pebble_app_bin_#{target}"

    Enum.map(reports, fn report ->
      existing = Map.get(report, :baseline, %{})

      Map.put(
        report,
        :baseline,
        manifest_baseline_compare(report, manifest, bin_key, existing)
      )
    end)
  end

  defp directory_baseline_compare(%{template: template, status: "ok"}, baseline_root, out_root, targets) do
    target = baseline_compare_target(targets)

    current_bin =
      template
      |> pebble_app_bin_path(out_root, target)
      |> file_size()

    baseline_bin =
      template
      |> pebble_app_bin_path(baseline_root, target)
      |> file_size()

    %{
      target: target,
      pebble_app_bin: metric_delta(current_bin, baseline_bin)
    }
  end

  defp directory_baseline_compare(_report, _baseline_root, _out_root, _targets), do: %{}

  defp manifest_baseline_compare(%{template: template} = report, manifest, bin_key, existing) do
    status = Map.get(report, :status) || Map.get(report, "status")
    compiler = Map.get(report, :compiler) || Map.get(report, "compiler")

    if status in ["ok", :ok] and is_map(compiler) do
      compare_manifest_baseline(template, compiler, manifest, bin_key, existing)
    else
      existing
    end
  end

  defp compare_manifest_baseline(template, compiler, manifest, bin_key, existing) do
    template_manifest = manifest_entry(manifest, template)
    current_generated_c = manifest_metric(compiler, :generated_c, :bytes)
    baseline_generated_c = manifest_metric_flat(template_manifest, "generated_c_bytes")
    current_bin = current_pebble_app_bin_bytes(existing)

    baseline_bin =
      case manifest_metric_flat(template_manifest, bin_key) do
        value when is_integer(value) -> value
        _ -> get_in(existing, [:pebble_app_bin, :baseline])
      end

    existing
    |> Map.put(:generated_c, metric_delta(current_generated_c, baseline_generated_c))
    |> Map.put(:pebble_app_bin, metric_delta(current_bin, baseline_bin))
  end

  defp manifest_entry(manifest, template) when is_map(manifest) do
    Map.get(manifest, template) || Map.get(manifest, to_string(template)) || %{}
  end

  defp manifest_metric(map, outer, inner) when is_map(map) do
    get_in(map, [outer, inner]) || get_in(map, [to_string(outer), to_string(inner)])
  end

  defp manifest_metric_flat(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp current_pebble_app_bin_bytes(%{pebble_app_bin: %{current: current}}) when is_integer(current),
    do: current

  defp current_pebble_app_bin_bytes(%{current_bin_bytes: current}) when is_integer(current), do: current
  defp current_pebble_app_bin_bytes(_), do: nil

  defp metric_delta(current, baseline) do
    case {current, baseline} do
      {current, baseline} when is_integer(current) and is_integer(baseline) ->
        %{current: current, baseline: baseline, delta: current - baseline}

      {current, nil} ->
        %{current: current, baseline: nil, delta: nil}

      {nil, baseline} ->
        %{current: nil, baseline: baseline, delta: nil}

      _ ->
        %{current: nil, baseline: nil, delta: nil}
    end
  end

  defp baseline_compare_target(:all), do: "flint"
  defp baseline_compare_target([target | _]), do: target
  defp baseline_compare_target(_), do: "flint"

  defp pebble_app_bin_path(template, workspace_root, target) do
    Path.join([
      workspace_root,
      template,
      ".pebble-sdk/app/build",
      target,
      "pebble-app.bin"
    ])
  end

  defp enforce_regression_budget!(reports, max_bin_regression, max_generated_c_regression) do
    regressions =
      reports
      |> Enum.flat_map(&regression_messages(&1, max_bin_regression, max_generated_c_regression))

    if regressions != [] do
      Mix.raise("size regression over budget:\n" <> Enum.join(regressions, "\n"))
    end

    :ok
  end

  defp regression_messages(report, max_bin_regression, max_generated_c_regression) do
    baseline = Map.get(report, :baseline, %{})

    bin_msg =
      case Map.get(baseline, :pebble_app_bin) do
        %{delta: delta} when is_integer(delta) and delta > max_bin_regression ->
          ["#{report.template}: pebble-app.bin grew by #{delta} bytes (budget #{max_bin_regression})"]

        %{delta: delta} when is_integer(delta) ->
          legacy_bin_regression(report.template, delta, max_bin_regression)

        _ ->
          legacy_bin_regression_from_flat(report, max_bin_regression)
      end

    generated_c_msg =
      case Map.get(baseline, :generated_c) do
        %{delta: delta} when is_integer(delta) and delta > max_generated_c_regression ->
          [
            "#{report.template}: elmc_generated.c grew by #{delta} bytes (budget #{max_generated_c_regression})"
          ]

        _ ->
          []
      end

    bin_msg ++ generated_c_msg
  end

  defp legacy_bin_regression(_template, _delta, max) when max < 0, do: []

  defp legacy_bin_regression(template, delta, max) when delta > max,
    do: ["#{template}: pebble-app.bin grew by #{delta} bytes (budget #{max})"]

  defp legacy_bin_regression(_template, _delta, _max), do: []

  defp legacy_bin_regression_from_flat(%{template: template, baseline: %{delta_bytes: delta}}, max)
       when is_integer(delta) and delta > max,
       do: ["#{template}: pebble-app.bin grew by #{delta} bytes (budget #{max})"]

  defp legacy_bin_regression_from_flat(_report, _max), do: []
end
