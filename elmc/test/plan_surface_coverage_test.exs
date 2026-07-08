defmodule Elmc.PlanSurfaceCoverageTest do
  use ExUnit.Case, async: false

  @moduletag :plan_surface

  @fixture Path.expand("fixtures/pebble_surface_project", __DIR__)

  test "reports Main lowering coverage for pebble_surface_project" do
    out_dir = Path.expand("tmp/plan_surface_coverage", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, result} =
             Elmc.compile(@fixture, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true,
               plan_ir_mode: :shadow
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

    report = Elmc.Backend.Plan.PrimaryCoverage.main_functions_report(decl_map)

    assert report.total > 0
    assert report.lowered == report.total,
           "expected full Main coverage, got #{report.lowered}/#{report.total}: #{inspect(Enum.take(report.failed, 8))}"
  end

  test "pebble_surface_project primary emits plan C for all Main functions" do
    out_dir = Path.expand("tmp/plan_surface_primary", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, result} =
             Elmc.compile(@fixture, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true,
               plan_ir_mode: :primary
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

    report = Elmc.Backend.Plan.PrimaryCoverage.main_functions_report(decl_map, ir: result.ir)

    assert report.lowered == report.total

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    parse_hour_body = Elmc.Test.CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_parseHourFromTimeString")
    assert parse_hour_body =~ "plan block"
    assert parse_hour_body =~ "string_left"

    view_append_body = Elmc.Test.CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_view_commands_append")
    assert view_append_body =~ "parseHourFromTimeString"
    assert view_append_body =~ "elmc_fn_Main_parseHourFromTimeString_native("

    refute Enum.any?(result.layout_coercion_diagnostics, &(&1["code"] == "plan_primary_fallback"))
  end

  test "lowers parseHourFromTimeString string pipeline" do
    out_dir = Path.expand("tmp/plan_surface_string_lower", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, result} =
             Elmc.compile(@fixture, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true,
               plan_ir_mode: :shadow
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

    decl = Map.fetch!(decl_map, {"Main", "parseHourFromTimeString"})

    assert {:ok, plan} =
             Elmc.Backend.Plan.Lower.Function.lower(decl, "Main", decl_map, rc_required: false)

    dump = Elmc.Backend.Plan.Debug.dump(plan)
    assert dump =~ "string_left"
    assert dump =~ "string_to_int"
    assert dump =~ "maybe_with_default"
    assert :ok = Elmc.Backend.Plan.Verify.run(plan)
  end
end
