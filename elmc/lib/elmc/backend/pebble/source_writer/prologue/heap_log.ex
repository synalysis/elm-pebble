defmodule Elmc.Backend.Pebble.SourceWriter.Prologue.HeapLog do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if defined(ELMC_PEBBLE_PLATFORM) && ELMC_PEBBLE_HEAP_LOG
    void elmc_pebble_heap_log(const char *label) {
      APP_LOG(
        APP_LOG_LEVEL_INFO,
        "ELMC heap %s used=%lu free=%lu",
        label ? label : "?",
        (unsigned long)heap_bytes_used(),
        (unsigned long)heap_bytes_free());
    }

    void elmc_pebble_render_diag_log(const char *phase, int render_seq, const ElmcPebbleApp *app) {
      if (app) {
        APP_LOG(
          APP_LOG_LEVEL_INFO,
          "ELMC render %s seq=%d heap_used=%lu heap_free=%lu scene_dirty=%d scene_bytes=%d scene_cmds=%d",
          phase ? phase : "?",
          render_seq,
          (unsigned long)heap_bytes_used(),
          (unsigned long)heap_bytes_free(),
          app->scene.dirty,
          app->scene.byte_count,
          app->scene.command_count);
      } else {
        elmc_pebble_heap_log(phase);
      }
    }
    #endif

    """
  end
end
