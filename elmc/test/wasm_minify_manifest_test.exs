defmodule Elmc.WasmMinifyManifestTest do
  use ExUnit.Case, async: false

  alias Elmc.TestSupport.CachedCompile
  alias Elmc.Backend.Wasm.{Artifacts, ProjectWriter}

  @fixture Path.expand("fixtures/wasm_web_div_project", __DIR__)

  test "web builds minify exports and ship a slim runtime manifest" do
    out_dir = Path.expand("tmp/wasm_minify_manifest", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} =
             CachedCompile.compile(@fixture, %{
               out_dir: out_dir,
               targets: [:wasm],
               web: true,
               entry_module: "Main",
               strip_dead_code: true,
               wasm_strict: false
             })

    runtime = out_dir |> ProjectWriter.manifest_path() |> File.read!() |> Jason.decode!()
    debug = out_dir |> ProjectWriter.debug_manifest_path() |> File.read!() |> Jason.decode!()
    wat = File.read!(ProjectWriter.wat_path(out_dir))

    assert runtime["minified"] == true
    assert runtime["entry_export"] == "elmc_fn_Main_main"
    assert is_integer(runtime["closure_count"])
    assert is_map(runtime["constructor_tags"])
    assert is_map(runtime["constructor_arities"])
    assert is_list(runtime["immortal_strings"])
    refute Map.has_key?(runtime, "closures")
    refute Map.has_key?(runtime, "imports")
    refute Map.has_key?(runtime, "functions")
    refute Map.has_key?(runtime, "plan_coverage")
    refute Map.has_key?(runtime, "stub_functions")

    assert debug["entry_export"] == "elmc_fn_Main_main"
    assert is_map(debug["constructor_tags"])
    assert is_list(debug["functions"])
    assert is_list(debug["closures"])
    assert is_list(debug["stub_functions"])
    assert Enum.all?(debug["closures"], &is_map/1)
    assert ProjectWriter.stub_functions(out_dir) == debug["stub_functions"]

    assert wat =~ ~s|(export "elmc_fn_Main_main")|
    assert wat =~ ~s|(export "memory")|

    exported_funcs =
      Regex.scan(~r/\(export "([^"]+)"\)/, wat)
      |> Enum.map(fn [_, name] -> name end)
      |> Enum.reject(&(&1 == "memory"))

    assert "elmc_fn_Main_main" in exported_funcs

    Enum.each(exported_funcs, fn name ->
      assert name == "elmc_fn_Main_main" or Regex.match?(~r/^c\d+$/, name),
             "unexpected export when minified: #{name}"
    end)

    summary = Artifacts.read_summary(out_dir)
    assert summary.available == true
    assert summary.function_count > 0
    assert is_map(summary.plan_coverage)
  end

  test "read_summary recovers skipped functions from the minified debug sidecar" do
    out_dir = Path.expand("tmp/wasm_minify_debug_summary", __DIR__)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(out_dir, "wasm"))

    File.write!(
      ProjectWriter.manifest_path(out_dir),
      Jason.encode!(%{
        "contract" => "elmc.wasm_manifest.v1",
        "version" => 1,
        "minified" => true,
        "entry_export" => "elmc_fn_Main_main"
      })
    )

    File.write!(
      ProjectWriter.debug_manifest_path(out_dir),
      Jason.encode!(%{
        "functions" => [],
        "skipped" => [
          %{
            "module" => "Main",
            "name" => "main",
            "reason" => "{:unsupported, %{op: :unsupported, target: nil, kind: nil}}"
          }
        ],
        "plan_coverage" => %{
          "reachable" => %{"failed_count" => 1, "lowered" => 0, "total" => 1}
        }
      })
    )

    summary = Artifacts.read_summary(out_dir)
    assert summary.available == true
    assert summary.function_count == 0
    assert summary.skipped_count == 1
    assert hd(summary.skipped).module == "Main"
    assert hd(summary.skipped).name == "main"
    assert summary.plan_coverage["reachable"]["failed_count"] == 1
  end

  test "wasm_strict fails when Main.main cannot be lowered" do
    root = Path.expand("fixtures/wasm_web_four_tuple_project", __DIR__)
    out_dir = Path.expand("tmp/wasm_web_four_tuple", __DIR__)
    File.rm_rf!(out_dir)

    case CachedCompile.compile(root, %{
           out_dir: out_dir,
           targets: [:wasm],
           web: true,
           entry_module: "Main",
           strip_dead_code: true,
           wasm_strict: true
         }) do
      {:error, {:compile_diagnostics, diags}} when is_list(diags) ->
        assert Enum.any?(diags, fn diag ->
                 diag["code"] in [
                   "wasm_unsupported_function",
                   "wasm_web_kernel_unimplemented",
                   "wasm_empty_exports",
                   "plan_primary_gap"
                 ]
               end)

      {:error, _other} ->
        :ok

      {:ok, _result} ->
        flunk("unsupported Main.main must not compile to an empty WASM module")
    end
  end

  test "wasm_export_all disables minify for probes" do
    out_dir = Path.expand("tmp/wasm_export_all_manifest", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} =
             CachedCompile.compile(@fixture, %{
               out_dir: out_dir,
               targets: [:wasm],
               web: true,
               entry_module: "Main",
               strip_dead_code: true,
               wasm_strict: false,
               wasm_export_all: true
             })

    runtime = out_dir |> ProjectWriter.manifest_path() |> File.read!() |> Jason.decode!()
    wat = File.read!(ProjectWriter.wat_path(out_dir))

    refute runtime["minified"] == true
    assert is_list(runtime["functions"])
    refute File.exists?(ProjectWriter.debug_manifest_path(out_dir))
    assert wat =~ ~s|(export "elmc_fn_Main_main")|
    assert wat =~ ~s|(export "elmc_fn_Html_div")| or wat =~ ~s|(export "elmc_fn_Html_text")|
  end
end
