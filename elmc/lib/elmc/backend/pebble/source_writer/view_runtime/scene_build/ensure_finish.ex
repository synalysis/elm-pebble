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
      elmc_pebble_clear_view_cache(app);
      app->scene.dirty = 0;
    #if ELMC_PEBBLE_SCENE_CACHE_ENABLED
      app->scene_draw_byte_offset = 0;
    #endif
    #if ELMC_PEBBLE_DIRTY_REGION_ENABLED
      if (!app->prev_scene.bytes || app->prev_scene.byte_count <= 0) {
        elmc_pebble_scene_mark_full_dirty(app);
      } else {
        elmc_pebble_scene_compute_dirty_rect(app);
      }
    #endif
      elmc_pebble_scene_trim_capacity(app);
      ELMC_PEBBLE_SCENE_LOG("elmc-scene ensure ok cmds=%d bytes=%d cap=%d",
              app->scene.command_count, app->scene.byte_count, app->scene.byte_capacity);
      ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_ensure_scene", 0);
    }
"""
  end
end
