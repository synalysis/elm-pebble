defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.Lifecycle.RebuildInvalidate.InvalidateScene do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    void elmc_pebble_invalidate_scene(ElmcPebbleApp *app) {
      if (!app) return;
    #if ELMC_PEBBLE_SCENE_CACHE_ENABLED || ELMC_PEBBLE_APLITE_DIRECT_VIEW_ACTIVE
      elmc_pebble_mark_scene_dirty(app);
      app->scene_draw_byte_offset = 0;
    #endif
    #if ELMC_PEBBLE_DIRTY_REGION_ENABLED
      elmc_pebble_scene_mark_full_dirty(app);
    #endif
    }
    """
  end
end
