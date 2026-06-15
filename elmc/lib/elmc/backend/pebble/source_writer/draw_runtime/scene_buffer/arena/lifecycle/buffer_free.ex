defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.Lifecycle.BufferFree do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static void elmc_pebble_scene_buffer_free_for_app(ElmcPebbleApp *app, ElmcPebbleSceneBuffer *scene) {
      (void)app;
      if (!scene) return;
    #if ELMC_PEBBLE_SCENE_CHUNK_SIZE > 0
      elmc_pebble_scene_chunks_free(scene);
    #endif
      if (scene->bytes && !elmc_pebble_scene_using_static(scene)) {
        free(scene->bytes);
      }
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
      elmc_pebble_scene_discard_build(app);
      elmc_pebble_scene_buffer_free_for_app(app, &app->scene);
    }

    static void elmc_pebble_scene_free(ElmcPebbleApp *app) {
      if (!app) return;
      elmc_pebble_scene_buffer_free_for_app(app, &app->scene);
    #if ELMC_PEBBLE_DIRTY_REGION_ENABLED
      elmc_pebble_scene_buffer_free_for_app(app, &app->prev_scene);
      app->dirty_rect_valid = 0;
      app->dirty_rect_full = 1;
    #endif
    }

"""
  end
end
