defmodule Elmc.Runtime.AllocProbe do
  @moduledoc """
  Host-only snapshots and diffs across `ELMC_RC_TRACK` and `ELMC_ALLOC_TRACK`.

  Compile harnesses with `-DELMC_ALLOC_PROBE=1` (implies RC + malloc tracking).
  """

  @spec header_declarations() :: String.t()
  def header_declarations do
    """
    #ifndef ELMC_ALLOC_PROBE
    #define ELMC_ALLOC_PROBE 0
    #endif

    #if ELMC_ALLOC_PROBE && !ELMC_RC_TRACK
    #undef ELMC_RC_TRACK
    #define ELMC_RC_TRACK 1
    #endif

    #if ELMC_ALLOC_PROBE && !ELMC_ALLOC_TRACK
    #undef ELMC_ALLOC_TRACK
    #define ELMC_ALLOC_TRACK 1
    #endif

    #if ELMC_ALLOC_PROBE
    #include <stdio.h>

    typedef struct ElmcAllocProbeSnap {
      uint32_t rc_live;
      uint64_t rc_allocated;
      uint64_t rc_released;
      uint32_t rc_next_id;
    #if ELMC_ALLOC_TRACK
      uint32_t malloc_live;
      uint32_t malloc_next_id;
    #endif
    } ElmcAllocProbeSnap;

    void elmc_alloc_probe_snap(ElmcAllocProbeSnap *snap);
    void elmc_alloc_probe_diff(const ElmcAllocProbeSnap *before, const char *label, FILE *out);
    int elmc_alloc_probe_diff_balanced(const ElmcAllocProbeSnap *before, const char *label, FILE *out);
    #endif
    """
  end

  @spec source_impl() :: String.t()
  def source_impl do
    """
    #if ELMC_ALLOC_PROBE

    void elmc_alloc_probe_snap(ElmcAllocProbeSnap *snap) {
      if (!snap) return;
      snap->rc_live = elmc_rc_track_live_count();
      snap->rc_allocated = elmc_rc_allocated_count();
      snap->rc_released = elmc_rc_released_count();
      snap->rc_next_id = elmc_rc_track_next_alloc_id();
    #if ELMC_ALLOC_TRACK
      snap->malloc_live = elmc_alloc_track_live_count();
      snap->malloc_next_id = elmc_alloc_track_next_alloc_id();
    #endif
    }

    void elmc_alloc_probe_diff(const ElmcAllocProbeSnap *before, const char *label, FILE *out) {
      if (!before) return;
      if (!out) out = stderr;
      ElmcAllocProbeSnap after = {0};
      elmc_alloc_probe_snap(&after);

      int64_t rc_net = (int64_t)(after.rc_allocated - before->rc_allocated) -
                       (int64_t)(after.rc_released - before->rc_released);
      int32_t rc_live_delta = (int32_t)after.rc_live - (int32_t)before->rc_live;
    #if ELMC_ALLOC_TRACK
      int32_t malloc_live_delta = (int32_t)after.malloc_live - (int32_t)before->malloc_live;
    #endif

      fprintf(out,
              "probe %s: rc_live %+d rc_net %+lld",
              label ? label : "?",
              rc_live_delta,
              (long long)rc_net);
    #if ELMC_ALLOC_TRACK
      fprintf(out, " malloc_live %+d", malloc_live_delta);
    #endif
      fprintf(out, "\\n");

      if (rc_net != 0 || rc_live_delta != 0) {
        elmc_rc_track_dump_since(before->rc_next_id, out);
      }
    #if ELMC_ALLOC_TRACK
      if (malloc_live_delta != 0) {
        elmc_alloc_track_dump_since(before->malloc_next_id, out);
      }
    #endif
    }

    int elmc_alloc_probe_diff_balanced(const ElmcAllocProbeSnap *before, const char *label, FILE *out) {
      if (!before) return 0;
      ElmcAllocProbeSnap after = {0};
      elmc_alloc_probe_snap(&after);

      int64_t rc_net = (int64_t)(after.rc_allocated - before->rc_allocated) -
                       (int64_t)(after.rc_released - before->rc_released);
    #if ELMC_ALLOC_TRACK
      int32_t malloc_live_delta = (int32_t)after.malloc_live - (int32_t)before->malloc_live;
      if (malloc_live_delta != 0) {
        elmc_alloc_probe_diff(before, label, out);
        return 0;
      }
    #endif

      if (rc_net != 0) {
        elmc_alloc_probe_diff(before, label, out);
        return 0;
      }

      return 1;
    }

    #endif
    """
  end
end
