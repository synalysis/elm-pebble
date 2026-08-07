defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.Lifecycle.BufferFree do
  @moduledoc false
  alias Elmc.Types, as: Types


  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static void elmc_pebble_scene_buffer_detach(ElmcPebbleSceneBuffer *scene) {
      if (!scene) return;
    #if ELMC_PEBBLE_SCENE_CHUNK_SIZE > 0
      elmc_pebble_scene_chunks_free(scene);
    #endif
      scene->bytes = NULL;
      scene->byte_count = 0;
      scene->byte_capacity = 0;
      scene->command_count = 0;
      scene->hash = 0;
      scene->dirty = 1;
    }

    static void elmc_pebble_scene_abort_build(ElmcPebbleApp *app) {
      if (!app) return;
      elmc_pebble_clear_view_cache(app);
    #if ELMC_PEBBLE_DIRTY_REGION_ENABLED
      /* Drop the incomplete rebuild slot; restore the previous good frame. */
      elmc_pebble_scene_buffer_detach(&app->scene);
      if (app->prev_scene.bytes && app->prev_scene.byte_count > 0) {
        app->scene = app->prev_scene;
        app->prev_scene.bytes = NULL;
        app->prev_scene.byte_count = 0;
        app->prev_scene.byte_capacity = 0;
        app->prev_scene.command_count = 0;
        app->prev_scene.hash = 0;
        app->prev_scene.dirty = 0;
        app->scene.dirty = 1;
        return;
      }
    #elif ELMC_PEBBLE_SCENE_POOL_SLOTS >= 2 && ELMC_PEBBLE_SCENE_CACHE_ENABLED
      if (app->scene_rebuild_fallback_byte_count > 0) {
        app->scene.pool_slot = app->scene_rebuild_fallback_slot;
        elmc_pebble_scene_pool_sync_from_slot(&app->scene);
        app->scene.byte_count = app->scene_rebuild_fallback_byte_count;
        app->scene.command_count = app->scene_rebuild_fallback_command_count;
        app->scene.dirty = 1;
        app->scene_rebuild_fallback_byte_count = 0;
        app->scene_rebuild_fallback_command_count = 0;
        return;
      }
    #endif
      elmc_pebble_scene_discard_build(app);
      elmc_pebble_scene_buffer_detach(&app->scene);
    }

    static void elmc_pebble_scene_free(ElmcPebbleApp *app) {
      if (!app) return;
      elmc_pebble_scene_buffer_detach(&app->scene);
    #if ELMC_PEBBLE_DIRTY_REGION_ENABLED
      elmc_pebble_scene_buffer_detach(&app->prev_scene);
    #endif
      elmc_pebble_scene_pool_free_all();
    #if ELMC_PEBBLE_DIRTY_REGION_ENABLED
      app->dirty_rect_valid = 0;
      app->dirty_rect_full = 1;
    #endif
    }

"""
  end
end
