defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.DirtyRegion.Compute.Reset do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static void elmc_pebble_scene_compute_dirty_rect(ElmcPebbleApp *app) {
      if (!app) return;
      app->dirty_rect_valid = 0;
      app->dirty_rect_full = 1;
      elmc_rect_set(&app->dirty_rect, 0, 0, 0, 0);

    """
  end
end
