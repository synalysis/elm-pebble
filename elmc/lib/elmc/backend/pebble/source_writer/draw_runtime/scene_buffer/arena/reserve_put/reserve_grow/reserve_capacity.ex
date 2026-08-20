defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.ReservePut.ReserveGrow.ReserveCapacity do
  @moduledoc false
  alias Elmc.Types, as: Types


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
      int next_capacity = elmc_pebble_scene_next_capacity(app->scene.byte_capacity, min_capacity);
      unsigned char *next = (unsigned char *)realloc(app->scene.bytes, (size_t)next_capacity);
      if (!next) {
        elmc_pebble_scene_note_grow_fail(
            next_capacity, app->scene.byte_capacity, app->scene.byte_count);
    #if defined(ELMC_PEBBLE_APP_TIGHT_RAM)
        free(app->scene.bytes);
        app->scene.bytes = NULL;
        app->scene.byte_capacity = 0;
    #endif
        return -2;
      }
      app->scene.bytes = next;
      app->scene.byte_capacity = next_capacity;
      return 0;
    #endif
    }

    """
  end
end
