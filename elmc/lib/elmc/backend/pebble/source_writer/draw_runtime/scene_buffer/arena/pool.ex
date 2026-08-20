defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.Pool do
  @moduledoc false
  alias Elmc.Types, as: Types


  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    /* Tight-RAM realloc often cannot grow in place: the heap has enough
       total free bytes but not a contiguous old+new hole. Remember the
       size we wanted, free the current slot, and let the next empty
       alloc malloc that size after the old block is back on the heap. */
    #if defined(ELMC_PEBBLE_APP_TIGHT_RAM)
    static int elmc_pebble_scene_grow_hint = 0;
    #ifndef ELMC_PEBBLE_SCENE_GROW_RETRY_MAX
    #define ELMC_PEBBLE_SCENE_GROW_RETRY_MAX 8
    #endif
    #endif

    static int elmc_pebble_scene_next_capacity(int current, int min_capacity) {
      int next = current > 0 ? current : 0;
      while (next < min_capacity) {
        if (next == 0) {
          int first = ELMC_PEBBLE_SCENE_INITIAL_CAPACITY;
    #if defined(ELMC_PEBBLE_APP_TIGHT_RAM)
          if (elmc_pebble_scene_grow_hint > first) first = elmc_pebble_scene_grow_hint;
    #endif
          next = first;
        } else if (next < ELMC_PEBBLE_SCENE_INITIAL_CAPACITY) {
          next += ELMC_PEBBLE_SCENE_GROW_CHUNK;
        } else {
    #if defined(ELMC_PEBBLE_APP_TIGHT_RAM)
          /* Exact-need grows (+1/+2 per command) fragment the heap; realloc
             then fails even when heap_bytes_free() is still >1KB. */
          next += ELMC_PEBBLE_SCENE_GROW_CHUNK;
          if (next < min_capacity) next = min_capacity;
    #else
          next *= 2;
    #endif
        }
      }
      return next;
    }

    static void elmc_pebble_scene_clear_grow_hint(void) {
    #if defined(ELMC_PEBBLE_APP_TIGHT_RAM)
      elmc_pebble_scene_grow_hint = 0;
    #endif
    }

    static int elmc_pebble_scene_should_retry_grow(int *attempts) {
    #if defined(ELMC_PEBBLE_APP_TIGHT_RAM)
      if (elmc_pebble_scene_grow_hint > 0 && attempts &&
          *attempts < ELMC_PEBBLE_SCENE_GROW_RETRY_MAX) {
        *attempts += 1;
        return 1;
      }
    #else
      (void)attempts;
    #endif
      return 0;
    }

    static void elmc_pebble_scene_note_grow_fail(int next_capacity, int have, int used) {
    #if defined(ELMC_PEBBLE_PLATFORM)
      APP_LOG(APP_LOG_LEVEL_ERROR,
              "elmc scene buffer alloc failed need=%d have=%d used=%d free=%lu",
              next_capacity,
              have,
              used,
              (unsigned long)heap_bytes_free());
    #else
      (void)used;
    #endif
    #if defined(ELMC_PEBBLE_APP_TIGHT_RAM)
    #ifndef ELMC_PEBBLE_SCENE_GROW_HINT_CAP
    #define ELMC_PEBBLE_SCENE_GROW_HINT_CAP 1024
    #endif
      if (have <= 0) {
        /* Hinted empty-slot malloc failed; do not climb further. */
        elmc_pebble_scene_grow_hint = 0;
      } else {
        /* Restart at the size realloc wanted, not 2x — a doubled malloc
           fails on a fragmented heap even when need itself would fit. */
        int hint = next_capacity;
        if (hint > ELMC_PEBBLE_SCENE_GROW_HINT_CAP) hint = ELMC_PEBBLE_SCENE_GROW_HINT_CAP;
        elmc_pebble_scene_grow_hint = hint;
      }
    #endif
      elmc_pebble_note_runtime_stats(NULL);
    #if !defined(ELMC_PEBBLE_APP_TIGHT_RAM)
      (void)next_capacity;
      (void)have;
    #endif
    }

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
      int next_capacity = elmc_pebble_scene_next_capacity(slot->capacity, min_capacity);
      /* realloc may grow in place; on failure the old pointer stays valid. */
      unsigned char *grown = (unsigned char *)realloc(slot->bytes, (size_t)next_capacity);
      if (!grown) {
        elmc_pebble_scene_note_grow_fail(next_capacity, slot->capacity, scene->byte_count);
    #if defined(ELMC_PEBBLE_APP_TIGHT_RAM)
        /* Free-then-restart: keep the last-good frame in the other slot and
           return this block so the next empty malloc can use the hole. */
        free(slot->bytes);
        slot->bytes = NULL;
        slot->capacity = 0;
        scene->bytes = NULL;
        scene->byte_capacity = 0;
    #endif
        return -2;
      }
      slot->bytes = grown;
      slot->capacity = next_capacity;
      elmc_pebble_scene_pool_sync_from_slot(scene);
      return 0;
    }

    static void elmc_pebble_scene_pool_release_slot(int slot) {
      if (slot < 0 || slot >= ELMC_PEBBLE_SCENE_POOL_SLOTS) return;
      free(elmc_pebble_scene_pool[slot].bytes);
      elmc_pebble_scene_pool[slot].bytes = NULL;
      elmc_pebble_scene_pool[slot].capacity = 0;
    }

    static void elmc_pebble_scene_pool_release_unused(const ElmcPebbleSceneBuffer *keep) {
    #if defined(ELMC_PEBBLE_APP_TIGHT_RAM)
      int keep_slot = (keep && elmc_pebble_scene_using_pool(keep)) ? keep->pool_slot : -1;
      int keep_cap = (keep_slot >= 0) ? elmc_pebble_scene_pool[keep_slot].capacity : 0;
      for (int i = 0; i < ELMC_PEBBLE_SCENE_POOL_SLOTS; i++) {
        if (i == keep_slot) continue;
        /* Drop a same-view double-buffer copy. Keep a larger unused slot so
         * a later heavier view can reuse it instead of reallocating. */
        if (elmc_pebble_scene_pool[i].capacity > 0 &&
            elmc_pebble_scene_pool[i].capacity <= keep_cap) {
          elmc_pebble_scene_pool_release_slot(i);
        }
      }
    #else
      (void)keep;
    #endif
    }

    static void elmc_pebble_scene_pool_free_all(void) {
      for (int i = 0; i < ELMC_PEBBLE_SCENE_POOL_SLOTS; i++) {
        elmc_pebble_scene_pool_release_slot(i);
      }
    }
    #else
    static void elmc_pebble_scene_pool_free_all(void) {
    }
    #endif

    """
  end
end
