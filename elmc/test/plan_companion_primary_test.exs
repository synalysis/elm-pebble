defmodule Elmc.PlanCompanionPrimaryTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Plan.PrimaryCoverage

  @moduletag :plan_surface

  @compile_opts %{
    direct_render_only: true,
    prune_runtime: true,
    prune_native_wrappers: true,
    pebble_int32: true,
    strip_dead_code: true,
    entry_module: "Main",
    plan_ir_mode: :primary,
    plan_ir_strict: true
  }

  for {fixture, label} <- [
        {"companion_weather_worker", "weather"},
        {"companion_reading_worker", "reading"}
      ] do
    @tag fixture: fixture
    test "companion #{label} worker reaches full plan-primary coverage", %{fixture: fixture} do
      project_dir = Path.expand("fixtures/#{fixture}", __DIR__)
      out_dir = Path.expand("tmp/plan_companion_primary_#{fixture}", __DIR__)
      File.rm_rf!(out_dir)

      assert {:ok, result} = Elmc.compile(project_dir, Map.put(@compile_opts, :out_dir, out_dir))

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

      reachable = PrimaryCoverage.reachable_report(decl_map, ir: result.ir, entry_module: "Main")

      assert reachable.lowered == reachable.total,
             "#{fixture} reachable plan coverage #{reachable.lowered}/#{reachable.total}: #{inspect(Enum.take(reachable.failed, 8))}"

      refute Enum.any?(result.layout_coercion_diagnostics || [], fn diag ->
               diag["code"] in ["plan_primary_fallback", "plan_primary_gap"] and
                 diag["severity"] == "error"
             end)

      assert result.plan_toolchain == %{mode: :primary, strict: true}

      generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

      assert generated_c =~ "plan block"
      assert generated_c =~ "view_commands_append"
      refute generated_c =~ "plan_primary_boxed"
      refute generated_c =~ ~r/elmc_unknown\b/
    end
  end
end
