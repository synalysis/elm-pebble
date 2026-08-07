defmodule Elmc.Backend.Pebble.HeaderWriter.SceneConfig.ConfigDefaults.ArenaSizing do
  @moduledoc false
  alias Elmc.Types, as: Types


  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    /* Platform sizing: INITIAL clears the mid-encode realloc cliff (a ~540B
       view overflowing a 512B first slot needs ~1.5KiB contiguous on grow and
       fails on tight heaps as SCENE_BUFFER_OVERFLOW → blank white draw).
       Pool double-buffering (prepare_rebuild + abort_build) keeps the last good
       frame when a later rebuild fails, so transient OOM does not gray the face. */
    #ifndef ELMC_PEBBLE_SCENE_INITIAL_CAPACITY
    #define ELMC_PEBBLE_SCENE_INITIAL_CAPACITY 1024
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

    /* Retained scene-byte pools: grow once per slot, never shrink or realloc per frame.
       Each slot is ~8B BSS on pebble_int32. Watchfaces typically keep 1–2 live scenes;
       4 leaves headroom under flint's 64KiB APP virtual-size uint16 limit. */
    #ifndef ELMC_PEBBLE_SCENE_POOL_SLOTS
    #if defined(PBL_PLATFORM_APLITE)
    #define ELMC_PEBBLE_SCENE_POOL_SLOTS 2
    #else
    #define ELMC_PEBBLE_SCENE_POOL_SLOTS 4
    #endif
    #endif

    #ifndef ELMC_PEBBLE_SCENE_STATIC_CAPACITY
    #define ELMC_PEBBLE_SCENE_STATIC_CAPACITY 0
    #endif

    #ifndef ELMC_PEBBLE_SCENE_CHUNK_SIZE
    #define ELMC_PEBBLE_SCENE_CHUNK_SIZE 0
    #endif

    """
  end
end
