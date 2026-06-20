defmodule Elmc.Backend.Pebble.SourceWriter.DispatchCore.Lifecycle.Init.SceneFields do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if ELMC_PEBBLE_SCENE_STATIC_CAPACITY > 0
      elmc_pebble_scene_bind_static(&app->scene);
      app->scene.byte_count = 0;
      app->scene.pool_slot = -1;
    #else
      app->scene.bytes = NULL;
      app->scene.byte_capacity = 0;
      app->scene.pool_slot = 0;
    #if ELMC_PEBBLE_SCENE_CHUNK_SIZE > 0
      app->scene.chunks = NULL;
    #endif
    #endif
      app->scene.command_count = 0;
      app->scene.hash = 0;
      app->scene.dirty = 1;
    #if ELMC_PEBBLE_SCENE_CACHE_ENABLED
      app->scene_draw_byte_offset = 0;
    #endif
    """
  end
end
