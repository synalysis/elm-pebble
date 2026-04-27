defmodule Elmc.MultiModuleTest do
  use ExUnit.Case

  alias ElmEx.IR.TopoSort

  test "modules are sorted in dependency order" do
    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    {:ok, project} = ElmEx.Frontend.Bridge.load_project(project_dir)
    {:ok, ir} = ElmEx.IR.Lowerer.lower_project(project)
    {:ok, sorted} = TopoSort.sort_modules(ir)

    module_names = Enum.map(sorted, & &1.name)

    # Companion.Types should come before Companion.Internal
    # since Internal imports Types
    types_idx = Enum.find_index(module_names, &(&1 == "Companion.Types"))
    internal_idx = Enum.find_index(module_names, &(&1 == "Companion.Internal"))

    if types_idx != nil and internal_idx != nil do
      assert types_idx < internal_idx,
             "Companion.Types (#{types_idx}) should come before Companion.Internal (#{internal_idx})"
    end
  end

  test "namespaced C symbols contain module prefix" do
    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    out_dir = Path.expand("tmp/multi_module", __DIR__)
    File.rm_rf!(out_dir)
    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, strip_dead_code: false})

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    # All function definitions should have module-namespaced symbols
    assert String.contains?(generated_c, "elmc_fn_Main_init")
    assert String.contains?(generated_c, "elmc_fn_Main_update")
    assert String.contains?(generated_c, "elmc_fn_Main_view")
    assert String.contains?(generated_c, "elmc_fn_CoreCompliance_foldSum")
    assert String.contains?(generated_c, "elmc_fn_Pebble_Cmd_none")
    assert String.contains?(generated_c, "elmc_fn_Pebble_Events_onTick")

    # No un-namespaced function definitions (except lambdas)
    lines = String.split(generated_c, "\n")
    function_defs = Enum.filter(lines, &String.contains?(&1, "ElmcValue *elmc_fn_"))

    bad_defs =
      Enum.reject(function_defs, fn line ->
        # Should have module prefix: elmc_fn_Module_name
        Regex.match?(~r/elmc_fn_[A-Z][A-Za-z0-9]*(_[A-Za-z0-9]+)+\(/, line)
      end)

    assert bad_defs == [], "Found un-namespaced function definitions: #{inspect(bad_defs)}"
  end

  test "qualified_constructor_project compiles with correct cross-module symbols" do
    project_dir = Path.expand("fixtures/qualified_constructor_project", __DIR__)
    out_dir = Path.expand("tmp/multi_module_qual", __DIR__)
    File.rm_rf!(out_dir)
    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, strip_dead_code: false})

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    # Main module functions should be present with module prefix
    assert String.contains?(generated_c, "elmc_fn_Main_")
    # A and B only define union types (no functions), so they won't
    # have elmc_fn_ entries — but constructor tags from A and B
    # should be resolved in Main's pattern matches and constructor calls
    assert String.contains?(generated_c, "elmc_fn_Main_fromA")
    assert String.contains?(generated_c, "elmc_fn_Main_fromB")
    assert String.contains?(generated_c, "elmc_fn_Main_matchA")
    assert String.contains?(generated_c, "elmc_fn_Main_matchB")
  end

  test "write_project_multi generates per-module files and link manifest" do
    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    out_dir = Path.expand("tmp/multi_module_files", __DIR__)
    File.rm_rf!(out_dir)

    {:ok, project} = ElmEx.Frontend.Bridge.load_project(project_dir)
    {:ok, ir} = ElmEx.IR.Lowerer.lower_project(project)
    :ok = Elmc.Runtime.Generator.write_runtime(Path.join(out_dir, "runtime"))
    :ok = Elmc.Backend.CCodegen.write_project_multi(ir, out_dir)

    # Per-module headers should exist
    assert File.exists?(Path.join(out_dir, "c/elmc_Main.h"))
    assert File.exists?(Path.join(out_dir, "c/elmc_Main.c"))

    # Link manifest should exist and be valid JSON
    manifest_path = Path.join(out_dir, "link_manifest.json")
    assert File.exists?(manifest_path)
    {:ok, manifest} = Jason.decode(File.read!(manifest_path))
    assert is_list(manifest["modules"])
    assert length(manifest["modules"]) > 0

    # Each module entry should have required fields
    Enum.each(manifest["modules"], fn mod ->
      assert is_binary(mod["module"])
      assert is_binary(mod["header"])
      assert is_binary(mod["source"])
      assert is_list(mod["functions"])
    end)
  end
end
