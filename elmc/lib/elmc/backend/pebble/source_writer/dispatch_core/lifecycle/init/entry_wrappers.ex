defmodule Elmc.Backend.Pebble.SourceWriter.DispatchCore.Lifecycle.Init.EntryWrappers do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    int elmc_pebble_init(ElmcPebbleApp *app, ElmcValue *flags) {
      return elmc_pebble_init_with_mode(app, flags, ELMC_PEBBLE_MODE_APP);
    }

    int elmc_pebble_init_with_mode(ElmcPebbleApp *app, ElmcValue *flags, int run_mode) {
      ELMC_PEBBLE_GENERATED_TRACE_ENTER("elmc_pebble_init_with_mode");
      if (!app) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_init_with_mode", -1);
      app->initialized = 0;
      app->run_mode = run_mode;
      app->has_prev_ui = 0;
      app->prev_window_id = 0;
      app->prev_layer_id = 0;
      app->prev_ops_hash = 0;
    #if !defined(ELMC_PEBBLE_DIRECT_VIEW_SCENE)
      app->stream_view_result = NULL;
    #endif
    """
  end
end
