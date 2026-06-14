defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.ReservePut.ReserveGrow.TrimCapacity do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static void elmc_pebble_scene_trim_capacity(ElmcPebbleApp *app) {
    #if ELMC_PEBBLE_SCENE_CHUNK_SIZE > 0
      (void)app;
    #elif ELMC_PEBBLE_SCENE_TRIM_SLACK > 0
      if (!app || !app->scene.bytes || app->scene.byte_count <= 0) return;
      if (elmc_pebble_scene_using_static(&app->scene)) return;
      int target = app->scene.byte_count + ELMC_PEBBLE_SCENE_TRIM_SLACK;
      if (app->scene.byte_capacity <= target) return;
      unsigned char *next = (unsigned char *)realloc(app->scene.bytes, (size_t)target);
      if (!next) return;
      app->scene.bytes = next;
      app->scene.byte_capacity = target;
    #else
      (void)app;
    #endif
    }

    """
  end
end
