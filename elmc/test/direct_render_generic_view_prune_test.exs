defmodule Elmc.DirectRenderGenericViewPruneTest do
  use ExUnit.Case, async: false

  alias Elmc.Test.CCodegenExtract

  @source_template Path.expand("../../ide/priv/project_templates/watchface_yes", __DIR__)

  test "color-only direct render prunes generic Main.view and faceOps while keeping view_commands_append" do
    project_dir = Path.expand("tmp/yes_generic_view_prune_project", __DIR__)
    out_dir = Path.expand("tmp/yes_generic_view_prune_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(@source_template, project_dir)

    File.write!(
      Path.join(project_dir, "elm.json"),
      Jason.encode!(%{
        "type" => "application",
        "source-directories" => [
          "src",
          "protocol/src",
          "../../../../packages/elm-pebble/elm-watch/src"
        ],
        "elm-version" => "0.19.1",
        "dependencies" => %{
          "direct" => %{"elm/core" => "1.0.5", "elm/json" => "1.1.3", "elm/time" => "1.0.0"},
          "indirect" => %{}
        },
        "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
      })
    )

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               direct_render_only: true,
               prune_runtime: true,
               pebble_int32: true,
               strip_dead_code: true
             })

    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated =~ "elmc_fn_Main_view_commands_append"

    view_body =
      case Regex.run(~r/static RC elmc_fn_Main_view_commands_append[\s\S]*?^}/m, generated) do
        [section] -> section
        _ -> flunk("missing elmc_fn_Main_view_commands_append body")
      end

    refute view_body =~ "elmc_fn_Main_faceDisplay("
    assert view_body =~ "elmc_fn_Main_showCorners_native("
    assert view_body =~ "elmc_fn_Yes_Render_drawDial_commands_append"
    assert view_body =~ "owned[0]"
    assert generated =~ "elmc_polar_point_x("
    refute generated =~ "elmc_fn_Yes_Render_pointAt("

    draw_dial_body = CCodegenExtract.fn_impl_body(generated, "elmc_fn_Yes_Render_drawDial_commands_append")

    assert draw_dial_body =~ "direct_tick_minute_"
    assert draw_dial_body =~ "direct_tick_label_"
    assert draw_dial_body =~ "elmc_fn_Yes_Render_textAt_commands_append_native"
    refute draw_dial_body =~ "elmc_new_float(&rec_field"
    refute draw_dial_body =~ "drawScaleTick_commands_append"
    refute generated =~ "static RC elmc_fn_Yes_Render_drawScaleTick_commands_append("

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
    assert generated =~ "static RC elmc_fn_Yes_Layout_centerSquare_native"
    assert generated =~ "static RC elmc_fn_Main_cornerSlots"
    assert generated =~ "str_immortal_"
    refute generated =~ "elmc_new_string_take(\"Jan\")"
    refute generated =~ "elmc_new_string(&owned[0], \"N\")"
    refute generated =~ "elmc_fn_Main_weatherSlot_closure_0"
    refute generated =~ "elmc_fn_Main_availableWeatherModes_closure_0"
    refute generated =~ "elmc_fn_Main_pickSlot_closure_0"
    assert generated =~ "elmc_fn_Main_view_scene_append"
  end
end
