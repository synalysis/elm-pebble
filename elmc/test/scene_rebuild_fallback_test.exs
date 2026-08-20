defmodule Elmc.SceneRebuildFallbackTest do
  @moduledoc """
  Failed scene rebuilds must restore the last good encoded frame.

  Without pool double-buffering, `abort_build` detached the only scene buffer and
  the app template filled white → lasting gray face under heap pressure.
  """

  use ExUnit.Case, async: false

  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.Lifecycle.BufferFree
  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.Lifecycle.RebuildInvalidate.PrepareRebuild
  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.ValueHelpers.TextAndPath
  alias Elmc.Backend.Pebble.HeaderWriter.SceneConfig.StructDecls.AppStruct
  alias Elmc.Backend.Pebble.SourceWriter.ViewRuntime.SceneBuild.EnsureFinish
  alias Elmc.Backend.Pebble.SourceWriter.DispatchCore.Lifecycle.Init.SceneFields

  test "app struct carries rebuild fallback counts under scene cache" do
    body = AppStruct.body()
    assert body =~ "scene_rebuild_fallback_slot"
    assert body =~ "scene_rebuild_fallback_byte_count"
    assert body =~ "scene_rebuild_fallback_command_count"
  end

  test "init clears rebuild fallback fields" do
    body = SceneFields.body()
    assert body =~ "scene_rebuild_fallback_byte_count = 0"
    assert body =~ "scene_rebuild_fallback_command_count = 0"
  end

  test "prepare_scene_rebuild flips pool slot only when a complete frame exists" do
    body = PrepareRebuild.body()
    assert body =~ "ELMC_PEBBLE_SCENE_POOL_SLOTS >= 2"
    assert body =~ "scene_rebuild_fallback_byte_count = app->scene.byte_count"
    assert body =~ "if (app->scene.byte_count > 0)"
    assert body =~ "app->scene.pool_slot = app->scene.pool_slot == 0 ? 1 : 0"
  end

  test "abort_build restores fallback frame instead of blanking" do
    body = BufferFree.body()
    assert body =~ "scene_rebuild_fallback_byte_count > 0"
    assert body =~ "app->scene.byte_count = app->scene_rebuild_fallback_byte_count"
    assert body =~ "app->scene.command_count = app->scene_rebuild_fallback_command_count"
    # Dirty-region path also restores prev_scene.
    assert body =~ "app->prev_scene.bytes && app->prev_scene.byte_count > 0"
    assert body =~ "elmc_pebble_scene_using_static"
    assert body =~ "ELMC_PEBBLE_SCENE_STATIC_CAPACITY"
  end

  test "successful ensure clears fallback counts" do
    body = EnsureFinish.body()
    assert body =~ "scene_rebuild_fallback_byte_count = 0"
    assert body =~ "scene_rebuild_fallback_command_count = 0"
    assert body =~ "elmc_pebble_scene_pool_release_unused"
    assert body =~ "elmc_pebble_note_runtime_stats(app)"
  end

  test "runtime stats watermark logs only the elmc-stats contract" do
    body = Elmc.Backend.Pebble.SourceWriter.Prologue.RuntimeStats.body()
    assert body =~ "elmc-stats scene_bytes="
    assert body =~ "scene_cmds="
    assert body =~ "scene_cap="
    assert body =~ "heap_free="
    assert body =~ "heap_free_min="
    assert body =~ "elmc_pebble_note_runtime_stats"
    refute body =~ "elmc_stats_last_emit_s"
    assert body =~ "if (!changed && elmc_stats_emitted) return"
  end

  test "clean ensure skip does not log runtime stats" do
    body = Elmc.Backend.Pebble.SourceWriter.ViewRuntime.SceneBuild.EnsurePreamble.body()
    assert body =~ "elmc-scene ensure skip clean"
    refute body =~ "elmc_pebble_note_runtime_stats"
  end

  test "tight-RAM pool drops same-size leftover slots but keeps a larger unused view" do
    pool = Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.Pool.body()
    assert pool =~ "elmc_pebble_scene_pool_release_slot"
    assert pool =~ "elmc_pebble_scene_pool_release_unused"
    assert pool =~ "ELMC_PEBBLE_APP_TIGHT_RAM"
    assert pool =~ "capacity <= keep_cap"

    abort = BufferFree.body()
    assert abort =~ "elmc_pebble_scene_pool_release_slot(failed_slot)"
    assert abort =~ "No last-good frame"
  end

  test "app template skips white fill when scene bytes are empty" do
    template =
      Path.expand("../../ide/priv/pebble_app_template/src/c/pebble_app_template.c", __DIR__)
      |> File.read!()

    assert template =~ "keep the previous framebuffer until a good scene is available again"
    assert template =~ "if (s_elm_app.scene.byte_count <= 0)"
    assert template =~ "Do not immediately retry"
    assert template =~ "font_from_id_for_text"
    refute template =~ "font_from_id_for_height"
  end

  test "tight-RAM template shrinks font cache and sizes inbox from the protocol" do
    template =
      Path.expand("../../ide/priv/pebble_app_template/src/c/pebble_app_template.c", __DIR__)
      |> File.read!()

    assert template =~ "ELMC_PEBBLE_APP_TIGHT_RAM"
    assert template =~ "#define ELMC_FONT_CACHE_CAP 4"
    assert template =~ "ELMC_INBOX_MAX_TUPLES = (COMPANION_PROTOCOL_MAX_FIELDS) + 2"
    refute template =~ "static CompanionProtocolPhoneToWatchMessage s_companion_inbox_message;"
    assert template =~ "&s_companion_inbox_decoder.message"
  end

  test "64KB APP platforms reserve a BSS scene buffer instead of a heap pool" do
    body = Elmc.Backend.Pebble.HeaderWriter.SceneConfig.ConfigDefaults.ArenaSizing.body()
    assert body =~ "ELMC_PEBBLE_APP_TIGHT_RAM"
    assert body =~ "PBL_PLATFORM_BASALT"
    assert body =~ "PBL_PLATFORM_FLINT"
    assert body =~ "#define ELMC_PEBBLE_SCENE_INITIAL_CAPACITY 768"
    assert body =~ "#define ELMC_PEBBLE_SCENE_INITIAL_CAPACITY 512"
    assert body =~ "#define ELMC_PEBBLE_SCENE_INITIAL_CAPACITY 1024"
    assert body =~ "#define ELMC_PEBBLE_SCENE_STATIC_CAPACITY 768"
    assert body =~ "#define ELMC_PEBBLE_SCENE_STATIC_CAPACITY 512"
    assert body =~ "#define ELMC_PEBBLE_SCENE_POOL_SLOTS 0"
    assert body =~ "#define ELMC_PEBBLE_SCENE_POOL_SLOTS 4"
    refute body =~ "#define ELMC_PEBBLE_SCENE_INITIAL_CAPACITY 256"
  end

  test "scene pool grows with realloc instead of malloc+copy" do
    body = Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.Pool.body()
    assert body =~ "realloc(slot->bytes, (size_t)next_capacity)"
    refute body =~ "malloc((size_t)next_capacity)"
    assert body =~ "ELMC_PEBBLE_APP_TIGHT_RAM"
    assert body =~ "next += ELMC_PEBBLE_SCENE_GROW_CHUNK"
    assert body =~ "if (next < min_capacity) next = min_capacity;"
    refute body =~ ~r/^\s*next = min_capacity;$/m

    reserve =
      Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.ReservePut.ReserveGrow.ReserveCapacity.body()

    assert reserve =~ "elmc_pebble_scene_next_capacity"
    assert reserve =~ "elmc_pebble_scene_note_grow_fail"
  end

  test "tight-RAM realloc miss frees the slot and retries from a grow hint" do
    pool = Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.Pool.body()
    assert pool =~ "elmc_pebble_scene_grow_hint"
    assert pool =~ "if (elmc_pebble_scene_grow_hint > first) first = elmc_pebble_scene_grow_hint"
    assert pool =~ "elmc_pebble_scene_note_grow_fail"
    assert pool =~ "free(slot->bytes)"
    assert pool =~ "ELMC_PEBBLE_SCENE_GROW_HINT_CAP"

    preamble = Elmc.Backend.Pebble.SourceWriter.ViewRuntime.SceneBuild.EnsurePreamble.body()
    assert preamble =~ "elmc_pebble_ensure_retry:"
    assert preamble =~ "elmc_pebble_ensure_attempts"

    direct = Elmc.Backend.Pebble.SourceWriter.ViewRuntime.SceneBuild.DirectBuild.body(%{
      entry_view_scene_append: "elmc_fn_Main_view_scene_append"
    })
    assert direct =~ "elmc_pebble_scene_should_retry_grow"
    assert direct =~ "goto elmc_pebble_ensure_retry"

    finish = EnsureFinish.body()
    assert finish =~ "elmc_pebble_scene_clear_grow_hint"
  end

  test "path extra-size helper is compiled only when DRAW_PATH is on" do
    body = TextAndPath.body()
    assert body =~ "#if ELMC_PEBBLE_FEATURE_DRAW_PATH"
    assert body =~ "static int elmc_scene_path_extra_size"
  end
end
