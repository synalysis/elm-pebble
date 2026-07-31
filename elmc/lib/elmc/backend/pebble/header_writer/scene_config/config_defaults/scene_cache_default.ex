defmodule Elmc.Backend.Pebble.HeaderWriter.SceneConfig.ConfigDefaults.SceneCacheDefault do
  @moduledoc false
  alias Elmc.Types, as: Types


  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #ifndef ELMC_PEBBLE_SCENE_CACHE_ENABLED
    /* Encode the view once into a compact byte stream (deferred off the draw
       stack); draw decodes with a cursor. Same path on aplite and color. */
    #define ELMC_PEBBLE_SCENE_CACHE_ENABLED 1
    #endif

    #ifndef ELMC_PEBBLE_SCENE_STREAM_CMDS
    #define ELMC_PEBBLE_SCENE_STREAM_CMDS 0
    #endif

    #ifndef ELMC_PEBBLE_SCENE_BUILD_VERIFY
    /* Full decode pass after scene build catches encoder bugs; skip on device builds. */
    #if defined(ELMC_PEBBLE_PLATFORM) && !ELMC_PEBBLE_DEBUG_LOGS
    #define ELMC_PEBBLE_SCENE_BUILD_VERIFY 0
    #else
    #define ELMC_PEBBLE_SCENE_BUILD_VERIFY 1
    #endif
    #endif

    """
  end
end
