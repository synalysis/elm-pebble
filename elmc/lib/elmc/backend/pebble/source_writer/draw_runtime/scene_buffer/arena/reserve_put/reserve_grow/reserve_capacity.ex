defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.ReservePut.ReserveGrow.ReserveCapacity do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static int elmc_pebble_scene_reserve_capacity(ElmcPebbleApp *app, int min_capacity) {
      if (!app || min_capacity < 0) return -1;
    #if ELMC_PEBBLE_SCENE_CHUNK_SIZE > 0
      while (app->scene.byte_capacity < min_capacity) {
        if (elmc_pebble_scene_chunk_append(&app->scene) != 0) return -2;
      }
      return 0;
    #else
    #if ELMC_PEBBLE_SCENE_POOL_SLOTS > 0
      if (app->scene.pool_slot < 0) {
        app->scene.pool_slot = 0;
      }
      if (elmc_pebble_scene_using_pool(&app->scene)) {
        return elmc_pebble_scene_pool_grow_slot(&app->scene, min_capacity);
      }
    #endif
    #if ELMC_PEBBLE_SCENE_STATIC_CAPACITY > 0
      if (!app->scene.bytes) {
        elmc_pebble_scene_bind_static(&app->scene);
      }
      if (elmc_pebble_scene_using_static(&app->scene)) {
        if (min_capacity > ELMC_PEBBLE_SCENE_STATIC_CAPACITY) return -2;
        return 0;
      }
    #endif
      if (app->scene.byte_capacity >= min_capacity) return 0;
      int next_capacity = app->scene.byte_capacity > 0 ? app->scene.byte_capacity : 0;
      while (next_capacity < min_capacity) {
        if (next_capacity == 0) {
          next_capacity = ELMC_PEBBLE_SCENE_INITIAL_CAPACITY;
        } else if (next_capacity < ELMC_PEBBLE_SCENE_INITIAL_CAPACITY) {
          next_capacity += ELMC_PEBBLE_SCENE_GROW_CHUNK;
        } else {
          next_capacity *= 2;
        }
      }
      unsigned char *next = (unsigned char *)malloc((size_t)next_capacity);
      if (!next) return -2;
      if (app->scene.bytes && app->scene.byte_count > 0) {
        memcpy(next, app->scene.bytes, (size_t)app->scene.byte_count);
      }
      free(app->scene.bytes);
      app->scene.bytes = next;
      app->scene.byte_capacity = next_capacity;
      return 0;
    #endif
    }

    """
  end
end
