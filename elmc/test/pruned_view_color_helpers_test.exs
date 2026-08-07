defmodule Elmc.PrunedViewColorHelpersTest do
  use ExUnit.Case, async: false

  @moduletag timeout: 300_000

  test "direct_render_only keeps Color helpers called from view_commands_append" do
    out_dir = Path.expand("tmp/pruned_view_color_helpers_codegen", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} =
             Elmc.TestSupport.TemplateCompile.compile_watch_template(
               "watchface_tutorial_complete",
               out_dir: out_dir,
               direct_render_only: true,
               prune_runtime: true,
               prune_native_wrappers: true,
               pebble_int32: true,
               strip_dead_code: true,
               codegen_profile: :size,
               plan_ir_mode: :primary,
               plan_ir_strict: true
             )

    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated =~ "elmc_fn_Main_view_commands_append"
    assert generated =~ ~r/Rc = elmc_fn_Main_pebbleColor\(&owned\[\d+\],/
    assert generated =~ ~r/static RC elmc_fn_Main_pebbleColor\(ElmcValue \*\*out,/
  end
end
