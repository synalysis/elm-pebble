defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.StaticCapacity do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if ELMC_PEBBLE_SCENE_STATIC_CAPACITY > 0
    static unsigned char elmc_pebble_scene_static_bytes[ELMC_PEBBLE_SCENE_STATIC_CAPACITY];

    static int elmc_pebble_scene_using_static(const ElmcPebbleSceneBuffer *scene) {
      return scene && scene->bytes == elmc_pebble_scene_static_bytes;
    }

    static void elmc_pebble_scene_bind_static(ElmcPebbleSceneBuffer *scene) {
      if (!scene) return;
      scene->bytes = elmc_pebble_scene_static_bytes;
      scene->byte_capacity = ELMC_PEBBLE_SCENE_STATIC_CAPACITY;
    }
    #else
    static int elmc_pebble_scene_using_static(const ElmcPebbleSceneBuffer *scene) {
      (void)scene;
      return 0;
    }
    #endif

"""
  end
end
