defmodule Elmc.Runtime.OwnedSlotsPool do
  @moduledoc """
  Nested BSS pool for large RC `owned[]` pointer frames on pebble_int32 builds.

  Replaces per-call `elmc_calloc`/`elmc_free` of `"owned_slots"` arrays that
  fragment the Pebble heap until scene encode fails.

  Pool storage lives in a static helper so prune_source keeps it with the
  acquire/release function bodies (mid-file file-scope statics would be dropped).

  Cap/depth default to 128×4 (host / unknown compile). When `write_runtime`
  can see generated C (`prune_from_dir`), the cap is the max
  `ELMC_OWNED_SLOT_COUNT` in that tree so a 64KB APP does not keep a 2KB
  unused pointer grid in BSS.
  """

  @default_cap 128
  @default_depth 4
  @pebble_compile_depth 3
  @min_compile_cap 24

  @type write_opts :: keyword()

  @spec header_declarations(write_opts()) :: String.t()
  def header_declarations(opts \\ []) do
    counts = owned_slot_counts_from_dir(Keyword.get(opts, :prune_from_dir))
    cap = pool_cap(opts, counts)
    depth = pool_depth(opts, counts)

    """
    #ifndef ELMC_OWNED_SLOTS_POOL_DEPTH
    #define ELMC_OWNED_SLOTS_POOL_DEPTH #{depth}
    #endif
    #ifndef ELMC_OWNED_SLOTS_POOL_CAP
    #define ELMC_OWNED_SLOTS_POOL_CAP #{cap}
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

  @spec pool_cap(write_opts(), [non_neg_integer()]) :: pos_integer()
  defp pool_cap(opts, counts) do
    case Keyword.get(opts, :owned_slots_pool_cap) do
      n when is_integer(n) and n > 0 -> n
      _ ->
        case counts do
          [] -> @default_cap
          _ -> max(Enum.max(counts), @min_compile_cap)
        end
    end
  end

  @spec pool_depth(write_opts(), [non_neg_integer()]) :: pos_integer()
  defp pool_depth(opts, counts) do
    case Keyword.get(opts, :owned_slots_pool_depth) do
      n when is_integer(n) and n > 0 -> n
      _ ->
        if Keyword.get(opts, :pebble_int32, false) and counts != [] do
          @pebble_compile_depth
        else
          @default_depth
        end
    end
  end

  @spec owned_slot_counts_from_dir(String.t() | nil) :: [pos_integer()]
  defp owned_slot_counts_from_dir(nil), do: []
  defp owned_slot_counts_from_dir(dir) when is_binary(dir) do
    dir
    |> Path.join("**/*.{c,h}")
    |> Path.wildcard()
    |> Enum.flat_map(fn path ->
      case File.read(path) do
        {:ok, body} ->
          ~r/ELMC_OWNED_SLOT_COUNT\s*=\s*(\d+)/
          |> Regex.scan(body)
          |> Enum.map(fn [_, n] -> String.to_integer(n) end)

        _ ->
          []
      end
    end)
  end
end
