defmodule Elmc.Backend.Pebble.SourceWriter.DispatchCore.Lifecycle.DispatchHooks do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static void elmc_pebble_invalidate_scene_for_dispatch(ElmcPebbleApp *app) {
      if (!app) return;
      elmc_pebble_clear_view_cache(app);
    #if !ELMC_PEBBLE_DIRTY_REGION_ENABLED && !ELMC_PEBBLE_SCENE_CACHE_ENABLED
      /* Streaming/chunked rebuild drops cached bytes immediately. Scene-cache watchfaces
         keep the last encoded scene visible until deferred ensure_scene finishes. */
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
    #if ELMC_PEBBLE_SCENE_CACHE_ENABLED || ELMC_PEBBLE_APLITE_DIRECT_VIEW_ACTIVE
      app->scene_draw_byte_offset = 0;
    #endif
    }

    static void elmc_pebble_prepare_dispatch(ElmcPebbleApp *app) {
      if (!app) return;
      elmc_pebble_heap_log("dispatch:prepare:before");
      elmc_pebble_heap_log("dispatch:prepare:after");
    }

    static int elmc_pebble_finish_dispatch(ElmcPebbleApp *app, int rc) {
      if (rc == 0 && elmc_worker_dispatch_needs_render(&app->worker)) {
        app->has_prev_ui = 0;
        app->prev_ops_hash = 0;
        elmc_pebble_invalidate_scene_for_dispatch(app);
      }
      elmc_pebble_heap_log("dispatch:after");
      return rc;
    }

"""
  end
end
