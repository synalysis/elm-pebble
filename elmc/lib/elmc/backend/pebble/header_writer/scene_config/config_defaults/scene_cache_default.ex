defmodule Elmc.Backend.Pebble.HeaderWriter.SceneConfig.ConfigDefaults.SceneCacheDefault do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #ifndef ELMC_PEBBLE_SCENE_CACHE_ENABLED
    #if ELMC_PEBBLE_APLITE_DIRECT_VIEW_ACTIVE
    /* Build the view into a compact byte stream once per invalidate; draw decodes with a cursor. */
    #define ELMC_PEBBLE_SCENE_CACHE_ENABLED 0
    #else
    /* Encode the view once into a compact byte stream; draw decodes with a cursor.
       Incremental dirty regions (prev_scene diff) stay off on Pebble targets until reliable. */
    #define ELMC_PEBBLE_SCENE_CACHE_ENABLED 1
    #endif
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
