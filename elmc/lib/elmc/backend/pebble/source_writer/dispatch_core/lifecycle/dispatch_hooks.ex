defmodule Elmc.Backend.Pebble.SourceWriter.DispatchCore.Lifecycle.DispatchHooks do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static void elmc_pebble_prepare_dispatch(ElmcPebbleApp *app) {
      if (!app) return;
      elmc_pebble_heap_log("dispatch:prepare:before");
      elmc_pebble_clear_view_cache(app);
    #if !ELMC_PEBBLE_DIRTY_REGION_ENABLED
      /* Invalidate encoded scene; retain materialized bytes to avoid heap churn on Aplite.
         Chunked rebuild uses scene.chunks; stale bytes are not read while dirty. */
      app->scene.byte_count = 0;
      app->scene.command_count = 0;
      app->scene.hash = 0;
    #if ELMC_PEBBLE_SCENE_POOL_SLOTS > 0
      elmc_pebble_scene_pool_sync_from_slot(&app->scene);
    #endif
    #if ELMC_PEBBLE_SCENE_CHUNK_SIZE > 0
      elmc_pebble_scene_chunks_free(&app->scene);
      app->scene.byte_capacity = 0;
    #endif
    #endif
      elmc_pebble_mark_scene_dirty(app);
    #if ELMC_PEBBLE_SCENE_CACHE_ENABLED
      app->scene_draw_byte_offset = 0;
    #endif
      elmc_pebble_heap_log("dispatch:prepare:after");
    }

    static int elmc_pebble_finish_dispatch(ElmcPebbleApp *app, int rc) {
      if (rc == 0) {
        app->has_prev_ui = 0;
        app->prev_ops_hash = 0;
        elmc_pebble_mark_scene_dirty(app);
      }
      elmc_pebble_heap_log("dispatch:after");
      return rc;
    }

"""
  end
end
