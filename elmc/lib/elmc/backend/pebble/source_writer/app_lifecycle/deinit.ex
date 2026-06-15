defmodule Elmc.Backend.Pebble.SourceWriter.AppLifecycle.Deinit do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    void elmc_pebble_deinit(ElmcPebbleApp *app) {
      if (!app) return;
      elmc_pebble_clear_view_cache(app);
      elmc_pebble_scene_free(app);
      if (app->initialized) {
        elmc_worker_deinit(&app->worker);
      }
      app->initialized = 0;
    }
    """
  end
end
