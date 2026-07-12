defmodule Elmc.Backend.Pebble.HeaderWriter.SceneConfig.ConfigDefaults.ArenaSizing do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #ifndef ELMC_PEBBLE_SCENE_INITIAL_CAPACITY
    #if ELMC_PEBBLE_APLITE_DIRECT_VIEW_ACTIVE
    #define ELMC_PEBBLE_SCENE_INITIAL_CAPACITY 256
    #else
    #define ELMC_PEBBLE_SCENE_INITIAL_CAPACITY 1024
    #endif
    #endif

    #ifndef ELMC_PEBBLE_SCENE_GROW_CHUNK
    #if defined(PBL_PLATFORM_APLITE)
    #define ELMC_PEBBLE_SCENE_GROW_CHUNK 32
    #else
    #define ELMC_PEBBLE_SCENE_GROW_CHUNK 64
    #endif
    #endif

    #ifndef ELMC_PEBBLE_SCENE_TRIM_SLACK
    #define ELMC_PEBBLE_SCENE_TRIM_SLACK 0
    #endif

    /* Retained scene-byte pools: grow once per slot, never shrink or realloc per frame. */
    #ifndef ELMC_PEBBLE_SCENE_POOL_SLOTS
    #if ELMC_PEBBLE_APLITE_DIRECT_VIEW_ACTIVE
    #define ELMC_PEBBLE_SCENE_POOL_SLOTS 0
    #else
    #define ELMC_PEBBLE_SCENE_POOL_SLOTS 10
    #endif
    #endif

    #ifndef ELMC_PEBBLE_SCENE_STATIC_CAPACITY
    #if ELMC_PEBBLE_APLITE_DIRECT_VIEW_ACTIVE
    #define ELMC_PEBBLE_SCENE_STATIC_CAPACITY 768
    #else
    #define ELMC_PEBBLE_SCENE_STATIC_CAPACITY 0
    #endif
    #endif

    #ifndef ELMC_PEBBLE_SCENE_CHUNK_SIZE
    #define ELMC_PEBBLE_SCENE_CHUNK_SIZE 0
    #endif

    """
  end
end
