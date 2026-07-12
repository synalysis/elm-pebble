defmodule Elmc.Backend.Pebble.SourceWriter.ViewRuntime.SceneBuild.EnsureFinish do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if ELMC_PEBBLE_SCENE_CHUNK_SIZE > 0
      {
        int mat_rc = elmc_pebble_scene_materialize_chunks(&app->scene);
        if (mat_rc != 0) {
          elmc_pebble_scene_abort_build(app);
          ELMC_DRAW_PATH_PROBE(ELMC_DRAW_PATH_ENSURE_SCENE_EXIT);
          ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_ensure_scene", mat_rc);
        }
      }
    #endif
    #if ELMC_PEBBLE_SCENE_CACHE_ENABLED && ELMC_PEBBLE_SCENE_BUILD_VERIFY
      {
        int verify_offset = 0;
        int verify_cmds = 0;
        while (verify_offset < app->scene.byte_count) {
          ElmcPebbleDrawCmd tmp;
          int dec_rc = elmc_pebble_scene_decode_record(
              app->scene.bytes, app->scene.byte_count, &verify_offset, &tmp);
          if (dec_rc != 0) {
            ELMC_PEBBLE_SCENE_LOG("elmc-scene verify decode failed rc=%d offset=%d cmds=%d bytes=%d",
                    dec_rc, verify_offset, app->scene.command_count, app->scene.byte_count);
            elmc_pebble_scene_abort_build(app);
            ELMC_DRAW_PATH_PROBE(ELMC_DRAW_PATH_ENSURE_SCENE_EXIT);
            ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_ensure_scene", -4);
          }
          verify_cmds += 1;
        }
        if (verify_cmds != app->scene.command_count) {
          ELMC_PEBBLE_SCENE_LOG("elmc-scene verify cmd mismatch decoded=%d recorded=%d bytes=%d",
                  verify_cmds, app->scene.command_count, app->scene.byte_count);
          elmc_pebble_scene_abort_build(app);
          ELMC_DRAW_PATH_PROBE(ELMC_DRAW_PATH_ENSURE_SCENE_EXIT);
          ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_ensure_scene", -5);
        }
      }
    #endif
      elmc_pebble_clear_view_cache(app);
      app->scene.dirty = 0;
    #if ELMC_PEBBLE_SCENE_CACHE_ENABLED || ELMC_PEBBLE_APLITE_DIRECT_VIEW_ACTIVE
      app->scene_draw_byte_offset = 0;
    #endif
    #if ELMC_PEBBLE_DIRTY_REGION_ENABLED
      if (!app->prev_scene.bytes || app->prev_scene.byte_count <= 0) {
        elmc_pebble_scene_mark_full_dirty(app);
      } else {
        elmc_pebble_scene_compute_dirty_rect(app);
      }
    #endif
    #if ELMC_PEBBLE_SCENE_POOL_SLOTS > 0
      elmc_pebble_scene_pool_sync_from_slot(&app->scene);
    #endif
    #if ELMC_PEBBLE_SCENE_TRIM_SLACK > 0
      elmc_pebble_scene_trim_capacity(app);
    #endif
      ELMC_PEBBLE_SCENE_LOG("elmc-scene ensure ok cmds=%d bytes=%d cap=%d",
              app->scene.command_count, app->scene.byte_count, app->scene.byte_capacity);
      ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_ensure_scene", 0);
    }
"""
  end
end
