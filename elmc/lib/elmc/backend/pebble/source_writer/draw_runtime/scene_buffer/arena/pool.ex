defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.Pool do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if ELMC_PEBBLE_SCENE_POOL_SLOTS > 0
    typedef struct {
      unsigned char *bytes;
      int capacity;
    } ElmcPebbleScenePoolSlot;

    static ElmcPebbleScenePoolSlot elmc_pebble_scene_pool[ELMC_PEBBLE_SCENE_POOL_SLOTS];

    static int elmc_pebble_scene_using_pool(const ElmcPebbleSceneBuffer *scene) {
      return scene && scene->pool_slot >= 0 && scene->pool_slot < ELMC_PEBBLE_SCENE_POOL_SLOTS;
    }

    static void elmc_pebble_scene_pool_sync_from_slot(ElmcPebbleSceneBuffer *scene) {
      if (!elmc_pebble_scene_using_pool(scene)) return;
      ElmcPebbleScenePoolSlot *slot = &elmc_pebble_scene_pool[scene->pool_slot];
      scene->bytes = slot->bytes;
      scene->byte_capacity = slot->capacity;
    }

    static int elmc_pebble_scene_pool_grow_slot(ElmcPebbleSceneBuffer *scene, int min_capacity) {
      if (!scene || min_capacity < 0) return -1;
      if (!elmc_pebble_scene_using_pool(scene)) return -1;
      ElmcPebbleScenePoolSlot *slot = &elmc_pebble_scene_pool[scene->pool_slot];
      if (slot->capacity >= min_capacity) {
        elmc_pebble_scene_pool_sync_from_slot(scene);
        return 0;
      }
      int next_capacity = slot->capacity > 0 ? slot->capacity : 0;
      while (next_capacity < min_capacity) {
        if (next_capacity == 0) {
          next_capacity = ELMC_PEBBLE_SCENE_INITIAL_CAPACITY;
        } else if (next_capacity < ELMC_PEBBLE_SCENE_INITIAL_CAPACITY) {
          next_capacity += ELMC_PEBBLE_SCENE_GROW_CHUNK;
        } else {
          next_capacity *= 2;
        }
      }
      unsigned char *grown = (unsigned char *)malloc((size_t)next_capacity);
      if (!grown) return -2;
      if (slot->bytes && scene->byte_count > 0) {
        memcpy(grown, slot->bytes, (size_t)scene->byte_count);
      }
      free(slot->bytes);
      slot->bytes = grown;
      slot->capacity = next_capacity;
      elmc_pebble_scene_pool_sync_from_slot(scene);
      return 0;
    }

    static void elmc_pebble_scene_pool_free_all(void) {
      for (int i = 0; i < ELMC_PEBBLE_SCENE_POOL_SLOTS; i++) {
        free(elmc_pebble_scene_pool[i].bytes);
        elmc_pebble_scene_pool[i].bytes = NULL;
        elmc_pebble_scene_pool[i].capacity = 0;
      }
    }
    #else
    static int elmc_pebble_scene_using_pool(const ElmcPebbleSceneBuffer *scene) {
      (void)scene;
      return 0;
    }

    static void elmc_pebble_scene_pool_free_all(void) {
    }
    #endif

    """
  end
end
