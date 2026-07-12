defmodule Elmc.DirectRenderDeadViewHelpersTest do
  use ExUnit.Case, async: false

  alias Elmc.Test.CCodegenExtract

  @source_fixture Path.expand("fixtures/simple_project", __DIR__)
  @template_main Path.expand("../../ide/priv/project_templates/game_2048/src/Main.elm", __DIR__)
  @project_dir Path.expand("tmp/dead_view_helpers_2048_project", __DIR__)
  @out_dir Path.expand("tmp/dead_view_helpers_2048_codegen", __DIR__)

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
               direct_render_only: true,
               plan_ir_mode: :primary,
               pebble_int32: true
             })

    {:ok, generated: File.read!(Path.join(@out_dir, "c/elmc_generated.c"))}
  end

  test "direct_render_only drops generic view subgraph helpers when scene path inlines grid",
       %{generated: generated} do
    assert generated =~ "elmc_fn_Main_view_commands_append"
    refute generated =~ "static RC elmc_fn_Main_view("
    refute generated =~ "static RC elmc_fn_Main_drawCell("
    refute generated =~ "static RC elmc_fn_Main_boardLayout("
    refute generated =~ "elmc_fn_Main_view_closure_0"
  end

  test "prune_direct_generic drops generic view like direct_render_only for aplite dual path",
       %{generated: _generated} do
    out = Path.expand("tmp/dead_view_helpers_2048_aplite_codegen", __DIR__)
    File.rm_rf!(out)

    assert {:ok, _} =
             Elmc.compile(@project_dir, %{
               out_dir: out,
               entry_module: "Main",
               strip_dead_code: true,
               direct_render_only: false,
               prune_direct_generic: true,
               plan_ir_mode: :primary,
               pebble_int32: true,
               prod: true
             })

    generated = File.read!(Path.join(out, "c/elmc_generated.c"))
    pebble_c = File.read!(Path.join(out, "c/elmc_pebble.c"))
    pebble_h = File.read!(Path.join(out, "c/elmc_pebble.h"))
    worker_h = File.read!(Path.join(out, "c/elmc_worker.h"))

    assert generated =~ "elmc_fn_Main_view_commands_append"
    refute generated =~ "static RC elmc_fn_Main_view("
    refute generated =~ "static RC elmc_fn_Main_drawCell("
    refute generated =~ "static RC elmc_fn_Main_boardLayout("
    refute generated =~ "elmc_fn_Main_view_closure_0"
    assert pebble_c =~ "#define ELMC_PEBBLE_APPEND_FALLBACK_SCENE 1"
    assert pebble_h =~ "#define ELMC_PEBBLE_APLITE_DIRECT_VIEW_SCENE 1"
    assert pebble_h =~ "#define ELMC_PEBBLE_APLITE_DIRECT_VIEW_ACTIVE 0"
    assert pebble_h =~ "#define ELMC_PEBBLE_SCENE_CACHE_ENABLED 1"
    assert pebble_h =~ "#define ELMC_PEBBLE_SCENE_BUILD_VERIFY 0"
    assert pebble_h =~ "#define ELMC_PEBBLE_FEATURE_COMPACT_DRAW 1"
    assert worker_h =~ "#define ELMC_WORKER_LAST_DISPATCH_CMD_CAP 0"
    assert pebble_c =~ "#if ELMC_PEBBLE_SCENE_CACHE_ENABLED && ELMC_PEBBLE_SCENE_BUILD_VERIFY"
  end

  test "moveBoard pipeline fusion inlines row merge under plan primary", %{generated: generated} do
    assert generated =~ "elmc_fn_Main_moveBoard_native"
    assert generated =~ "row_score"
    refute generated =~ "static RC elmc_fn_Main_collapseRow("
    refute generated =~ "static RC elmc_fn_Main_merge("
    refute generated =~ "static RC elmc_fn_Main_orient("

    move_board = CCodegenExtract.fn_body(generated, "elmc_fn_Main_moveBoard_native")
    assert move_board =~ "elmc_row_major_fwd_perm"
    assert move_board =~ "out_buf[cmp_i] != src[cmp_i]"
    refute move_board =~ "elmc_row_major_perm_src_i"
    refute move_board =~ "spawn_after_choice < 0"
    refute move_board =~ "next_cells = elmc_list_nil()"
    assert move_board =~ "Rc = elmc_list_from_int_array_reuse(&next_cells"
    assert move_board =~ "CHECK_RC(Rc)"
  end

  test "view board loop keeps cons fallback for worker model cells on pebble_int32 builds",
       %{generated: _generated} do
    out = Path.expand("tmp/dead_view_helpers_2048_aplite_codegen", __DIR__)
    File.rm_rf!(out)

    assert {:ok, _} =
             Elmc.compile(@project_dir, %{
               out_dir: out,
               entry_module: "Main",
               strip_dead_code: true,
               direct_render_only: false,
               prune_direct_generic: true,
               plan_ir_mode: :primary,
               pebble_int32: true,
               prod: true
             })

    generated = File.read!(Path.join(out, "c/elmc_generated.c"))
    assert generated =~ "ELMC_TAG_INT_LIST"
    assert generated =~ "direct_cursor_"
  end

  test "update calls fused initialBoard_native with native seed", %{generated: generated} do
    assert generated =~ "elmc_fn_Main_initialBoard_native(&owned["
    assert generated =~ "elmc_as_int(owned["
  end
end
