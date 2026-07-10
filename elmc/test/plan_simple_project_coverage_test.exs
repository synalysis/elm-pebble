defmodule Elmc.PlanSimpleProjectCoverageTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Bytecode.Loader
  alias Elmc.Backend.Plan.PrimaryCoverage

  @moduletag :plan_surface
  @fixture Path.expand("fixtures/simple_project", __DIR__)

  test "simple_project Main helpers reach full plan lowering coverage" do
    out_dir = Path.expand("tmp/plan_simple_full_coverage", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, result} =
             Elmc.compile(@fixture, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false,
               plan_ir_mode: :primary,
               plan_ir_strict: true
             })

    Process.put(:elmc_constructor_tags, Elmc.Backend.CCodegen.IRQueries.constructor_tag_map(result.ir))

    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    decl_map =
      result.ir.modules
      |> Enum.flat_map(fn mod ->
        mod.declarations
        |> Enum.filter(&(&1.kind == :function))
        |> Enum.map(fn decl -> {{mod.name, decl.name}, decl} end)
      end)
      |> Map.new()

    report = PrimaryCoverage.main_functions_report(decl_map)

    expected = [
      "init",
      "update",
      "moveBoard",
      "view",
      "subscriptions",
      "probeHelper",
      "probeAdvanced",
      "probeScoreOf"
    ]

    failed_names = Map.new(report.failed, fn {m, n, _} -> {{m, n}, true} end)

    for name <- expected do
      assert Map.has_key?(decl_map, {"Main", name})
      refute Map.has_key?(failed_names, {"Main", name}), "expected #{name} to lower"
    end

    assert report.lowered == report.total,
           "expected full Main coverage, got #{report.lowered}/#{report.total}: #{inspect(Enum.take(report.failed, 5))}"

    fallbacks =
      (result.layout_coercion_diagnostics || [])
      |> Enum.filter(&(&1["code"] == "plan_primary_fallback"))

    assert fallbacks == []

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    refute generated_c =~ ~r/elmc_unknown\b/

    manifest_path = Path.join(out_dir, "bytecode/elmc_bytecode.manifest.json")
    assert File.exists?(manifest_path)

    {:ok, manifest} = Loader.load_manifest(manifest_path)
    main_cov = get_in(manifest, ["plan_coverage", "main"])

    assert main_cov["failed_count"] == 0
    assert main_cov["lowered"] == main_cov["total"]

    empty_cells = List.duplicate(0, 16)
    model = {:record, [empty_cells, 42, 0, 0, 0, 0, 0, 0, :round]}

    assert {:ok, 42} =
             Loader.run_manifest_entry(out_dir, {"Main", "probeScoreOf"}, params: [model])

    assert {:ok, 8} = Loader.run_manifest_entry(out_dir, {"Main", "probeAdvanced"}, params: [5])
    assert {:ok, 11} = Loader.run_manifest_entry(out_dir, {"Main", "probeAdvanced"}, params: [9])
  end
end
