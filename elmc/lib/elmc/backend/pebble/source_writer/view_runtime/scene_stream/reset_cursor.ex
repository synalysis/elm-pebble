defmodule Elmc.Backend.Pebble.SourceWriter.ViewRuntime.SceneStream.ResetCursor do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    void elmc_pebble_scene_reset_draw_cursor(ElmcPebbleApp *app) {
      if (!app) return;
    #if ELMC_PEBBLE_SCENE_CACHE_ENABLED || ELMC_PEBBLE_APLITE_DIRECT_VIEW_ACTIVE
      app->scene_draw_byte_offset = 0;
    #endif
    }

"""
  end
end
