defmodule Elmc.Backend.Pebble.HeaderWriter.ApiDecls.RuntimeApi do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    void elmc_pebble_clear_view_cache(ElmcPebbleApp *app);
    int elmc_pebble_tick(ElmcPebbleApp *app);
    int64_t elmc_pebble_active_subscriptions(ElmcPebbleApp *app);
    int64_t elmc_pebble_model_as_int(ElmcPebbleApp *app);
    int elmc_pebble_run_mode(ElmcPebbleApp *app);
    void elmc_pebble_deinit(ElmcPebbleApp *app);

    #if defined(ELMC_PEBBLE_PLATFORM) && ELMC_PEBBLE_HEAP_LOG
    void elmc_pebble_heap_log(const char *label);
    void elmc_pebble_render_diag_log(const char *phase, int render_seq, const ElmcPebbleApp *app);
    #else
    #define elmc_pebble_heap_log(label) do { (void)(label); } while (0)
    #define elmc_pebble_render_diag_log(phase, render_seq, app) \\
      do { \\
        (void)(phase); \\
        (void)(render_seq); \\
        (void)(app); \\
      } while (0)
    #endif
"""
  end
end
