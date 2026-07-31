defmodule Elmc.WasmMinifyManifestTest do
  use ExUnit.Case, async: false

  alias Elmc.TestSupport.CachedCompile
  alias Elmc.Backend.Wasm.ProjectWriter

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
