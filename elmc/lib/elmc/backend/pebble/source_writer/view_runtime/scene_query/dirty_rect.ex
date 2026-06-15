defmodule Elmc.Backend.Pebble.SourceWriter.ViewRuntime.SceneQuery.DirtyRect do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    int elmc_pebble_scene_dirty_rect(ElmcPebbleApp *app, ElmcPebbleRect *out_rect, int *out_full) {
      if (!app || !out_rect || !out_full) return -1;
      int rc = elmc_pebble_ensure_scene(app);
      if (rc != 0) return rc;
    #if ELMC_PEBBLE_DIRTY_REGION_ENABLED
      *out_full = app->dirty_rect_full || !app->dirty_rect_valid;
      *out_rect = app->dirty_rect;
      return app->dirty_rect_valid ? 1 : 0;
    #else
      *out_full = 1;
      out_rect->x = 0;
      out_rect->y = 0;
      out_rect->w = 0;
      out_rect->h = 0;
      return 0;
    #endif
    }

    """
  end
end
