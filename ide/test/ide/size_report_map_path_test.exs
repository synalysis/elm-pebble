defmodule Ide.SizeReportMapPathTest do
  use ExUnit.Case, async: true

  test "find_pebble_map_file prefers nested target build directories" do
    tmp = System.tmp_dir!() |> Path.join("ide_size_report_map_#{System.unique_integer()}")
    on_exit(fn -> File.rm_rf(tmp) end)

    build_dir = Path.join(tmp, "build")
    nested = Path.join(build_dir, "flint")
    File.mkdir_p!(nested)

    map_path = Path.join(nested, "pebble-app.map")
    File.write!(map_path, "placeholder\n")

    found = find_map(build_dir)
    assert found == map_path
  end

  # Mirrors Mix.Tasks.Ide.SizeReport.find_pebble_map_file/1
  defp find_map(build_dir) do
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

  test "baseline compare reports pebble-app.bin delta when both trees exist" do
    tmp = System.tmp_dir!() |> Path.join("ide_size_report_base_#{System.unique_integer()}")
    on_exit(fn -> File.rm_rf(tmp) end)

    baseline_root = Path.join(tmp, "baseline")
    current_root = Path.join(tmp, "current")
    target = "flint"
    template = "game-2048"

    for {root, bytes} <- [{baseline_root, 100}, {current_root, 80}] do
      bin =
        Path.join([
          root,
          template,
          ".pebble-sdk/app/build",
          target,
          "pebble-app.bin"
        ])

      File.mkdir_p!(Path.dirname(bin))
      File.write!(bin, :binary.copy(<<0>>, bytes))
    end

    assert baseline_compare(template, baseline_root, current_root, target) == %{
             target: target,
             pebble_app_bin: %{current: 80, baseline: 100, delta: -20}
           }
  end

  defp baseline_compare(template, baseline_root, current_root, target) do
    current = pebble_app_bin_path(template, current_root, target) |> file_size()
    baseline = pebble_app_bin_path(template, baseline_root, target) |> file_size()

    %{
      target: target,
      pebble_app_bin: %{
        current: current,
        baseline: baseline,
        delta: if(is_integer(current) and is_integer(baseline), do: current - baseline, else: nil)
      }
    }
  end

  defp pebble_app_bin_path(template, workspace_root, target) do
    Path.join([workspace_root, template, ".pebble-sdk/app/build", target, "pebble-app.bin"])
  end

  defp file_size(path) do
    case File.stat(path) do
      {:ok, %{type: :regular, size: size}} -> size
      _ -> nil
    end
  end

  test "mix task applies manifest baseline to compiler generated_c bytes" do
    ide_root = Path.expand("../..", __DIR__)
    manifest = Path.join(ide_root, "priv/size_report_baselines/flint.json")
    assert File.regular?(manifest)

    {output, 0} =
      System.cmd(
        "mix",
        [
          "ide.size_report",
          "--templates",
          "game-2048",
          "--out",
          Path.join(System.tmp_dir!(), "ide_size_report_mix_#{System.unique_integer()}"),
          "--baseline-manifest",
          manifest
        ],
        cd: ide_root,
        env: [{"MIX_ENV", "test"}],
        stderr_to_stdout: true
      )

    json = extract_json!(output)
    report = Enum.find(json["templates"], &(&1["template"] == "game-2048"))
    assert report["status"] == "ok"

    assert get_in(report, ["baseline", "generated_c", "current"]) ==
             get_in(report, ["compiler", "generated_c", "bytes"])

    assert get_in(report, ["baseline", "generated_c", "baseline"]) == 78_758
  end

  defp extract_json!(output) do
    starts = for {start, _} <- :binary.matches(output, "{"), do: start

    Enum.find_value(Enum.reverse(starts), fn start ->
      case Jason.decode(String.slice(output, start..-1//1)) do
        {:ok, %{"templates" => _} = json} -> json
        _ -> nil
      end
    end)
    |> case do
      %{} = json -> json
      _ -> flunk("could not find size report JSON in mix output")
    end
  end
end
