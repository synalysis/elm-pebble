defmodule Elmc.PlanYesRenderLowerTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Plan.Lower.Function, as: PlanLower
  alias Elmc.Backend.Plan.PrimaryCoverage
  alias Elmc.Test.CCodegenExtract
  alias Elmc.TestSupport.TemplateCompile

  @moduletag :plan_surface
  @moduletag :slow

  test "watchface_yes fromScreen decl args match cdecl param names" do
    {:ok, result} =
      TemplateCompile.compile_watch_template("watchface_yes",
        plan_ir_mode: :primary,
        out_dir: Path.expand("tmp/plan_yes_from_screen_args", __DIR__)
      )

    decl_map = TemplateCompile.decl_map_from_result(result)
    decl = Map.fetch!(decl_map, {"Yes.Layout", "fromScreen"})

    assert decl.args == ["screenW", "screenH"]

    {:ok, plan} = PlanLower.lower(decl, "Yes.Layout", decl_map, rc_required: true)

    assert Enum.map(plan.params, & &1.name) == ["screenW", "screenH"]

    load_params =
      plan.blocks
      |> Enum.flat_map(& &1.instrs)
      |> Enum.filter(&(&1.op == :load_param))

    assert Enum.all?(load_params, fn %{args: %{index: idx}} -> idx in [0, 1] end)

    const_c_exprs =
      plan.blocks
      |> Enum.flat_map(& &1.instrs)
      |> Enum.filter(&(&1.op == :const_c_expr))
      |> Enum.map(& &1.args.value)

    refute Enum.any?(const_c_exprs, &String.starts_with?(&1, "arg"))
  end

  test "watchface_yes Yes.Render and Yes.Layout lower without fallbacks" do
    out_dir = Path.expand("tmp/plan_yes_render_lower", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, result} =
             TemplateCompile.compile_watch_template("watchface_yes",
               plan_ir_mode: :primary,
               out_dir: out_dir
             )

    Process.put(:elmc_constructor_tags, Elmc.Backend.CCodegen.IRQueries.constructor_tag_map(result.ir))

    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    decl_map = TemplateCompile.decl_map_from_result(result)

    for {mod, name} <- [
          {"Yes.Render", "drawBottomRight"},
          {"Yes.Render", "drawBottomRightCountdown"},
          {"Yes.Render", "pointAt"},
          {"Yes.Layout", "fromScreen"}
        ] do
      decl = Map.fetch!(decl_map, {mod, name})

      assert {:ok, _plan} =
               PlanLower.lower(decl, mod, decl_map, rc_required: false),
             "expected plan lowering for #{mod}.#{name}"
    end

    yes_failed =
      PrimaryCoverage.report(decl_map, ir: result.ir).failed
      |> Enum.filter(fn {mod, _, _} -> String.starts_with?(mod, "Yes.") end)

    assert yes_failed == []

    refute Enum.any?(result.layout_coercion_diagnostics, &(&1["code"] == "plan_primary_fallback"))

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    point_at_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Yes_Render_pointAt")
    assert point_at_body =~ "plan block"
    assert point_at_body =~ "elmc_basics_sin"
    assert point_at_body =~ "elmc_new_float"

    draw_br_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Yes_Render_drawBottomRight")
    assert draw_br_body =~ "elmc_render_cmd6"
    refute draw_br_body =~ "drawVectorAt_native"

    init_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_init")
    assert init_body =~ "Rc = elmc_fn_Yes_Layout_fromScreen(&owned["
    refute init_body =~ "owned[5] = elmc_fn_Yes_Layout_fromScreen("

    from_screen_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Yes_Layout_fromScreen")
    refute from_screen_body =~ "elmc_as_int(arg2)"
    refute from_screen_body =~ "elmc_as_int(arg10)"
    assert from_screen_body =~ "screenH"
  end
end
