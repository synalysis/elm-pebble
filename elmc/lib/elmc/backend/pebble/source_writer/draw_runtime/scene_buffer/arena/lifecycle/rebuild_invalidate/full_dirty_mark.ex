defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.Lifecycle.RebuildInvalidate.FullDirtyMark do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if ELMC_PEBBLE_DIRTY_REGION_ENABLED
    static void elmc_pebble_scene_mark_full_dirty(ElmcPebbleApp *app) {
      if (!app) return;
      app->dirty_rect_valid = 0;
      app->dirty_rect_full = 1;
      app->dirty_rect.x = 0;
      app->dirty_rect.y = 0;
      app->dirty_rect.w = 0;
      app->dirty_rect.h = 0;
    }
    #endif

    """
  end
end
