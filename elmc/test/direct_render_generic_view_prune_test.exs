defmodule Elmc.DirectRenderGenericViewPruneTest do
  use ExUnit.Case, async: false

  @moduletag :slow

  alias Elmc.Test.CCodegenExtract

  test "color-only direct render prunes generic Main.view and faceOps while keeping view_commands_append" do
    out_dir = Path.expand("tmp/yes_generic_view_prune_codegen", __DIR__)
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

    view_body =
      case Regex.run(~r/static RC elmc_fn_Main_view_commands_append[\s\S]*?^}/m, generated) do
        [section] -> section
        _ -> flunk("missing elmc_fn_Main_view_commands_append body")
      end

    refute view_body =~ "elmc_fn_Main_faceDisplay("
    assert view_body =~ "elmc_fn_Main_showCorners"
    assert view_body =~ "elmc_as_bool" or view_body =~ "elmc_fn_Main_showCorners_native("
    refute view_body =~ "plan_primary_boxed_native_bool"
    refute view_body =~ ~r/if \(elmc_maybe_is_nothing\(owned\[\d+\]\)\) \{\s*\}/
    assert view_body =~ "elmc_maybe_is_just(owned["
    assert view_body =~ "elmc_fn_Yes_Render_drawDial_commands_append"
    assert view_body =~ "owned[0]"
    assert generated =~ "elmc_polar_point_x("
    refute generated =~ "elmc_fn_Yes_Render_pointAt("

    draw_dial_body = CCodegenExtract.fn_impl_body(generated, "elmc_fn_Yes_Render_drawDial_commands_append")

    assert draw_dial_body =~ "direct_tick_minute_"
    assert draw_dial_body =~ "direct_tick_label_"
    assert draw_dial_body =~ "elmc_fn_Yes_Render_textAt_commands_append_native"
    refute draw_dial_body =~ "elmc_new_float(&rec_field"
    assert draw_dial_body =~ "drawScaleTick_commands_append" or draw_dial_body =~ "direct_tick_minute_"

    refute generated =~ "static RC elmc_fn_Main_faceDisplay("
    refute generated =~ "static RC elmc_fn_Main_faceOps"
    refute generated =~ "static RC elmc_fn_Yes_Render_face"
    refute generated =~ "static RC elmc_fn_Yes_Render_drawCorners"
    refute generated =~ "static RC elmc_fn_Yes_Render_drawOuterScale("
    refute generated =~ "drawOuterScale_closure"
    refute generated =~ "static RC elmc_fn_Yes_Render_drawScaleTick("
    refute generated =~ "static RC elmc_fn_Yes_Render_draw24HourHand("
    refute generated =~ "static RC elmc_fn_Yes_Render_drawMoonPhase("
    refute generated =~ "static RC elmc_fn_Yes_Render_drawSunWindow("
    refute generated =~ "static RC elmc_fn_Yes_Render_pointAt("
    refute generated =~ "elmc_fn_Yes_Render_pointAt("
    refute generated =~ "elmc_fn_Main_faceOps("
    assert generated =~ "elmc_fn_Yes_Layout_centerSquare"
    assert generated =~ "static RC elmc_fn_Main_cornerSlots"
    assert generated =~ "str_immortal_"
    refute generated =~ "elmc_harness_new_string(\"Jan\")"
    refute generated =~ "elmc_new_string(&owned[0], \"N\")"
    refute generated =~ "elmc_fn_Main_weatherSlot_closure_0"
    refute generated =~ "elmc_fn_Main_availableWeatherModes_closure_0"
    assert generated =~ "elmc_fn_Main_view_scene_append"
  end
end
