defmodule Elmc.Backend.Pebble.HeaderWriter.SceneConfig.ConfigDefaults.ArenaSizing do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #ifndef ELMC_PEBBLE_SCENE_INITIAL_CAPACITY
    #define ELMC_PEBBLE_SCENE_INITIAL_CAPACITY 512
    #endif

    #ifndef ELMC_PEBBLE_SCENE_GROW_CHUNK
    #if defined(PBL_PLATFORM_APLITE)
    #define ELMC_PEBBLE_SCENE_GROW_CHUNK 32
    #else
    #define ELMC_PEBBLE_SCENE_GROW_CHUNK 64
    #endif
    #endif

    #ifndef ELMC_PEBBLE_SCENE_TRIM_SLACK
    #if defined(PBL_PLATFORM_APLITE)
    #define ELMC_PEBBLE_SCENE_TRIM_SLACK 16
    #else
    #define ELMC_PEBBLE_SCENE_TRIM_SLACK 0
    #endif
    #endif

    /* Optional fixed scene arena (BSS). Prefer chained heap chunks on Aplite instead. */
    #ifndef ELMC_PEBBLE_SCENE_STATIC_CAPACITY
    #define ELMC_PEBBLE_SCENE_STATIC_CAPACITY 0
    #endif

    #ifndef ELMC_PEBBLE_SCENE_CHUNK_SIZE
    #if defined(PBL_PLATFORM_APLITE)
    #define ELMC_PEBBLE_SCENE_CHUNK_SIZE 256
    #else
    #define ELMC_PEBBLE_SCENE_CHUNK_SIZE 0
    #endif
    #endif

    """
  end
end
