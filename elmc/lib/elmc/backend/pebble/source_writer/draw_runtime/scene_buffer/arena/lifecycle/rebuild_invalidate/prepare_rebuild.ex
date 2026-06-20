defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.Lifecycle.RebuildInvalidate.PrepareRebuild do
  @moduledoc false

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
    #else
      app->scene.byte_count = 0;
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
