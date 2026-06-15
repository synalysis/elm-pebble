defmodule Elmc.Backend.Pebble.HeaderWriter.SceneConfig.ConfigDefaults.SceneCacheDefault do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #ifndef ELMC_PEBBLE_SCENE_CACHE_ENABLED
    /* Encode the view once into a compact byte stream; draw decodes with a cursor.
       Incremental dirty regions (prev_scene diff) stay off on Pebble targets until reliable. */
    #define ELMC_PEBBLE_SCENE_CACHE_ENABLED 1
    #endif

    """
  end
end
