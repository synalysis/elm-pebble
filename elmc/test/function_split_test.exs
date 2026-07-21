defmodule Elmc.FunctionSplitTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.CCodegen.FunctionSplit
  alias Elmc.Backend.CCodegen.IRQueries
  alias Elmc.Test.CCodegenExtract

  defp compile_yes_project!(opts) do
    out_dir = Keyword.fetch!(opts, :out_dir)

    assert {:ok, %{ir: ir}} =
             Elmc.TestSupport.TemplateCompile.compile_watch_template("watchface_yes",
               out_dir: out_dir,
               direct_render_only: Keyword.get(opts, :direct_render_only, true),
               prune_runtime: Keyword.get(opts, :prune_runtime, true),
               pebble_int32: Keyword.get(opts, :pebble_int32, true),
               strip_dead_code: Keyword.get(opts, :strip_dead_code, true),
               keep_tmp: true
             )

    ir
  end

  defp yes_draw_dial_decl!(out_dir) do
    ir = compile_yes_project!(out_dir: out_dir)
    Map.fetch!(IRQueries.function_decl_map(ir), {"Yes.Render", "drawDial"})
  end

  test "drawDial split part0 keeps sunWindow in the first chunk" do
    out_dir = Path.expand("tmp/function_split_yes_plan_codegen", __DIR__)
    File.rm_rf!(out_dir)
    decl = yes_draw_dial_decl!(out_dir)

    {:ok, parts} = FunctionSplit.plan_parts_for_test(decl.expr, decl.args || [])
    {part0_names, _part0} = hd(parts)

    assert "sunWindow" in part0_names
    assert "moonBounds" in part0_names
    assert "center" in part0_names
  end

  test "drawDial direct render compiles without phantom zero-arg let calls" do
    out_dir = Path.expand("tmp/function_split_yes_codegen", __DIR__)
    File.rm_rf!(out_dir)

    compile_yes_project!(out_dir: out_dir)

    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated =~ "elmc_fn_Yes_Render_drawDial_commands_append"
    refute generated =~ "elmc_fn_Yes_Render_sunsetAngle(NULL"
    refute generated =~ "elmc_fn_Yes_Render_sunriseAngle(NULL"
    refute generated =~ "elmc_fn_Yes_Render_sunset(NULL"
    refute generated =~ "elmc_fn_Yes_Render_sunrise(NULL"
    refute generated =~ "elmc_fn_Yes_Render_sunWindow(NULL"

    draw_dial_body =
      CCodegenExtract.fn_body(generated, "elmc_fn_Yes_Render_drawDial_commands_append")

    assert draw_dial_body =~ "elmc_maybe_with_default"
    assert draw_dial_body =~ "elmc_fn_Yes_Layout_centerSquare"
    assert draw_dial_body =~ "ELMC_FIELD_MAIN_MODEL_SUN"
    refute draw_dial_body =~ "ELMC_FIELD_YES_RENDER_FACEDISPLAY_SUN"
    refute generated =~ "elmc_fn_Yes_Render_model"
  end
end
