defmodule Elmc.PrunedViewTextHelpersTest do
  use ExUnit.Case, async: false

  @source_fixture Path.expand("fixtures/simple_project", __DIR__)
  @template_main Path.expand("../../ide/priv/project_templates/watch_demo_wakeup/src/Main.elm", __DIR__)
  @project_dir Path.expand("tmp/pruned_view_text_helpers_project", __DIR__)
  @out_dir Path.expand("tmp/pruned_view_text_helpers_codegen", __DIR__)

  setup do
    File.rm_rf!(@project_dir)
    File.rm_rf!(@out_dir)
    File.cp_r!(@source_fixture, @project_dir)
    File.write!(Path.join(@project_dir, "src/Main.elm"), File.read!(@template_main))

    assert {:ok, _} =
             Elmc.compile(@project_dir, %{
               out_dir: @out_dir,
               entry_module: "Main",
               strip_dead_code: true,
               direct_render_only: false,
               prune_direct_generic: true,
               codegen_profile: :size,
               plan_ir_mode: :primary,
               pebble_int32: true
             })

    {:ok, generated: File.read!(Path.join(@out_dir, "c/elmc_generated.c"))}
  end

  test "pruned generic view keeps text helpers and lowers wakeup cmds", %{generated: generated} do
    assert generated =~ "elmc_fn_Main_view_commands_append"
    assert generated =~ "static RC elmc_fn_Main_launchLabel("
    assert generated =~ "elmc_fn_Main_launchLabel(&owned["
    refute generated =~ "elmc_fn_Pebble_Wakeup_"
    assert generated =~ "ELMC_PEBBLE_CMD_WAKEUP"
  end
end
