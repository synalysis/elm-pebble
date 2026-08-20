defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.Lifecycle.RebuildInvalidate.PrepareRebuild do
  @moduledoc false
  alias Elmc.Types, as: Types


  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static void elmc_pebble_prepare_scene_rebuild(ElmcPebbleApp *app) {
      if (!app) return;
    #if ELMC_PEBBLE_DIRTY_REGION_ENABLED
      elmc_pebble_scene_buffer_detach(&app->prev_scene);
      app->prev_scene = app->scene;
      app->scene.bytes = NULL;
      app->scene.byte_count = 0;
      app->scene.byte_capacity = 0;
      app->scene.pool_slot = app->prev_scene.pool_slot == 0 ? 1 : 0;
    #elif ELMC_PEBBLE_SCENE_POOL_SLOTS >= 2 && ELMC_PEBBLE_SCENE_CACHE_ENABLED
      /* Flip only when a complete frame exists. An empty first encode must grow
         the current slot; flipping would allocate a second buffer after a failed
         attempt whose bytes were still sitting in the unused slot. */
      app->scene_rebuild_fallback_slot = app->scene.pool_slot;
      app->scene_rebuild_fallback_byte_count = app->scene.byte_count;
      app->scene_rebuild_fallback_command_count = app->scene.command_count;
      if (app->scene.byte_count > 0) {
        app->scene.pool_slot = app->scene.pool_slot == 0 ? 1 : 0;
      }
      app->scene.byte_count = 0;
      elmc_pebble_scene_pool_sync_from_slot(&app->scene);
    #else
      app->scene.byte_count = 0;
    #if ELMC_PEBBLE_SCENE_STATIC_CAPACITY > 0
      if (!app->scene.bytes) {
        elmc_pebble_scene_bind_static(&app->scene);
      }
    #endif
    #if ELMC_PEBBLE_SCENE_POOL_SLOTS > 0
      elmc_pebble_scene_pool_sync_from_slot(&app->scene);
    #endif
    #if ELMC_PEBBLE_SCENE_CHUNK_SIZE > 0
      elmc_pebble_scene_chunks_free(&app->scene);
      /* byte_capacity tracks chunk reservation during build; reset before chunk append. */
      app->scene.byte_capacity = 0;
    #endif
    #endif
      app->scene.command_count = 0;
      app->scene.hash = 0;
      app->scene.dirty = 1;
    #if ELMC_PEBBLE_DIRTY_REGION_ENABLED
      app->dirty_rect_valid = 0;
      app->dirty_rect_full = 1;
    #endif
    }

    """
  end
end
