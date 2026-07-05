defmodule Elmc.FunctionSplitTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.CCodegen.FunctionSplit
  alias Elmc.Backend.CCodegen.IRQueries
  alias Elmc.Test.CCodegenExtract

  @source_template Path.expand("../../ide/priv/project_templates/watchface_yes", __DIR__)

  defp prepare_yes_project!(project_dir) do
    File.rm_rf!(project_dir)
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
  end

  defp yes_draw_dial_decl!(project_dir) do
    {:ok, %{ir: ir}} =
      Elmc.compile(project_dir, %{
        out_dir: Path.join(project_dir, ".ir-only"),
        entry_module: "Main",
        direct_render_only: true,
        prune_runtime: true,
        pebble_int32: true,
        strip_dead_code: true
      })

    Map.fetch!(IRQueries.function_decl_map(ir), {"Yes.Render", "drawDial"})
  end

  test "drawDial split part0 keeps sunWindow in the first chunk" do
    project_dir = Path.expand("tmp/function_split_yes_plan_project", __DIR__)
    prepare_yes_project!(project_dir)
    decl = yes_draw_dial_decl!(project_dir)

    {:ok, parts} = FunctionSplit.plan_parts_for_test(decl.expr, decl.args || [])
    {part0_names, _part0} = hd(parts)

    assert "sunWindow" in part0_names
    assert "moonBounds" in part0_names
    assert "center" in part0_names
  end

  test "drawDial direct render compiles without phantom zero-arg let calls" do
    project_dir = Path.expand("tmp/function_split_yes_project", __DIR__)
    out_dir = Path.expand("tmp/function_split_yes_codegen", __DIR__)
    prepare_yes_project!(project_dir)
    File.rm_rf!(out_dir)

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
