defmodule Elmc.Backend.Pebble.HeaderWriter.SceneConfig.ConfigDefaults.ArenaSizing do
  @moduledoc false
  alias Elmc.Types, as: Types


  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    /* Tight-RAM APP images (Aplite 24KB / Basalt·Chalk·Diorite·Flint 64KB).
       After companion AppMessages the heap is fragmented: realloc and even
       malloc(320) can fail with >1.5KB free. Reserve the scene in BSS at
       init so a full watch encode never needs a heap grow. Heap-backed
       first slots (256) only postpone the miss until the face overflows.
       Emery/Gabbro keep a malloc pool with a 1KB first slot. */
    #if defined(PBL_PLATFORM_APLITE) || defined(PBL_PLATFORM_BASALT) || defined(PBL_PLATFORM_CHALK) || defined(PBL_PLATFORM_DIORITE) || defined(PBL_PLATFORM_FLINT)
    #define ELMC_PEBBLE_APP_TIGHT_RAM 1
    #endif

    #ifndef ELMC_PEBBLE_SCENE_INITIAL_CAPACITY
    #if defined(PBL_PLATFORM_APLITE)
    #define ELMC_PEBBLE_SCENE_INITIAL_CAPACITY 512
    #elif defined(ELMC_PEBBLE_APP_TIGHT_RAM)
    #define ELMC_PEBBLE_SCENE_INITIAL_CAPACITY 768
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

    /* Tight-RAM: no heap scene pool. One BSS buffer is rebuilt in place.
       Larger platforms keep a 4-slot malloc pool. */
    #ifndef ELMC_PEBBLE_SCENE_POOL_SLOTS
    #if defined(ELMC_PEBBLE_APP_TIGHT_RAM)
    #define ELMC_PEBBLE_SCENE_POOL_SLOTS 0
    #else
    #define ELMC_PEBBLE_SCENE_POOL_SLOTS 4
    #endif
    #endif

    #ifndef ELMC_PEBBLE_SCENE_STATIC_CAPACITY
    #if defined(PBL_PLATFORM_APLITE)
    #define ELMC_PEBBLE_SCENE_STATIC_CAPACITY 512
    #elif defined(ELMC_PEBBLE_APP_TIGHT_RAM)
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
