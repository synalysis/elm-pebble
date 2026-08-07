defmodule Elmc.Runtime.OwnedSlotsPool do
  @moduledoc """
  Nested BSS pool for large RC `owned[]` pointer frames on pebble_int32 builds.

  Replaces per-call `elmc_calloc`/`elmc_free` of `"owned_slots"` arrays that
  fragment the Pebble heap until scene encode fails.

  Pool storage lives in a static helper so prune_source keeps it with the
  acquire/release function bodies (mid-file file-scope statics would be dropped).
  """

  @spec header_declarations() :: String.t()
  def header_declarations do
    """
    #ifndef ELMC_OWNED_SLOTS_POOL_DEPTH
    #define ELMC_OWNED_SLOTS_POOL_DEPTH 4
    #endif
    #ifndef ELMC_OWNED_SLOTS_POOL_CAP
    #define ELMC_OWNED_SLOTS_POOL_CAP 128
    #endif

    typedef struct {
      ElmcValue *frames[ELMC_OWNED_SLOTS_POOL_DEPTH][ELMC_OWNED_SLOTS_POOL_CAP];
      int depth;
    } ElmcOwnedSlotsPoolState;

    ElmcValue **elmc_owned_slots_acquire(int count);
    void elmc_owned_slots_release(ElmcValue **owned, int count);
    """
  end

  @spec source_impl() :: String.t()
  def source_impl do
    """
    static ElmcOwnedSlotsPoolState *elmc_owned_slots_pool_state(void) {
      static ElmcOwnedSlotsPoolState state;
      return &state;
    }

    ElmcValue **elmc_owned_slots_acquire(int count) {
      ElmcOwnedSlotsPoolState *state;
      ElmcValue **frame;
      if (count <= 0) return NULL;
      state = elmc_owned_slots_pool_state();
      if (count <= ELMC_OWNED_SLOTS_POOL_CAP && state->depth < ELMC_OWNED_SLOTS_POOL_DEPTH) {
        frame = state->frames[state->depth];
        memset(frame, 0, (size_t)count * sizeof(ElmcValue *));
        state->depth += 1;
        return frame;
      }
      /* Rare: deeper nesting or oversized frame — fall back to heap. */
      return (ElmcValue **)elmc_calloc((size_t)count, sizeof(ElmcValue *), "owned_slots");
    }

    void elmc_owned_slots_release(ElmcValue **owned, int count) {
      ElmcOwnedSlotsPoolState *state;
      (void)count;
      if (!owned) return;
      state = elmc_owned_slots_pool_state();
      if (state->depth > 0 && owned == state->frames[state->depth - 1]) {
        state->depth -= 1;
        return;
      }
      elmc_free(owned);
    }
    """
  end
end
