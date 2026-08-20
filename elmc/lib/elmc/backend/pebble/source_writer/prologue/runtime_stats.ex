defmodule Elmc.Backend.Pebble.SourceWriter.Prologue.RuntimeStats do
  @moduledoc false
  alias Elmc.Types, as: Types

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    /* Contract line for the IDE emulator panel. Emit once, then only when a
       scene watermark grows. Periodic APP_LOG fragments tight heaps. */
    #if defined(ELMC_PEBBLE_PLATFORM)
    static int elmc_stats_scene_bytes_max = 0;
    static int elmc_stats_scene_cmds_max = 0;
    static int elmc_stats_scene_cap = 0;
    static unsigned long elmc_stats_heap_free_min = 0;
    static int elmc_stats_emitted = 0;

    void elmc_pebble_note_runtime_stats(const ElmcPebbleApp *app) {
      unsigned long heap_free = (unsigned long)heap_bytes_free();
      int scene_bytes = app ? app->scene.byte_count : 0;
      int scene_cmds = app ? app->scene.command_count : 0;
      int scene_cap = app ? app->scene.byte_capacity : 0;
      int changed = 0;
      if (scene_bytes > elmc_stats_scene_bytes_max) {
        elmc_stats_scene_bytes_max = scene_bytes;
        changed = 1;
      }
      if (scene_cmds > elmc_stats_scene_cmds_max) {
        elmc_stats_scene_cmds_max = scene_cmds;
        changed = 1;
      }
      if (scene_cap > elmc_stats_scene_cap) {
        elmc_stats_scene_cap = scene_cap;
        changed = 1;
      }
      if (elmc_stats_heap_free_min == 0 || heap_free < elmc_stats_heap_free_min) {
        elmc_stats_heap_free_min = heap_free;
      }
      if (!changed && elmc_stats_emitted) return;
      elmc_stats_emitted = 1;
      APP_LOG(APP_LOG_LEVEL_INFO,
              "elmc-stats scene_bytes=%d scene_cmds=%d scene_cap=%d heap_free=%lu heap_free_min=%lu",
              elmc_stats_scene_bytes_max,
              elmc_stats_scene_cmds_max,
              elmc_stats_scene_cap,
              heap_free,
              elmc_stats_heap_free_min);
    }
    #else
    void elmc_pebble_note_runtime_stats(const ElmcPebbleApp *app) {
      (void)app;
    }
    #endif

    """
  end
end
