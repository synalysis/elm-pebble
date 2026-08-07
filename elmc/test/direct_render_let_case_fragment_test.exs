defmodule Elmc.DirectRenderLetCaseFragmentTest do
  use ExUnit.Case, async: false

  @moduletag :slow

  alias Elmc.Test.CCodegenExtract

  test "let-bound case of Maybe tuple stays in view_commands_append" do
    out_dir = Path.expand("tmp/yes_let_case_fragment_codegen", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} =
             Elmc.TestSupport.TemplateCompile.compile_watch_template("watchface_yes",
               out_dir: out_dir,
               direct_render_only: true,
               prune_runtime: true,
               pebble_int32: true,
               strip_dead_code: true
             )

    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated =~ "elmc_fn_Main_view_commands_append"
    assert generated =~ "elmc_fn_Yes_Render_drawDial_commands_append"

    draw_dial =
      CCodegenExtract.fn_impl_body(generated, "elmc_fn_Yes_Render_drawDial_commands_append")

    assert draw_dial =~ "moonriseMin" or draw_dial =~ "MOONRISEMIN" or
             draw_dial =~ "elmc_maybe_is_just"
    assert draw_dial =~ "coloredRadialWedge_commands_append" or
             draw_dial =~ "ELMC_RENDER_OP_FILL_RADIAL" or
             draw_dial =~ "fill_radial"
  end
end
