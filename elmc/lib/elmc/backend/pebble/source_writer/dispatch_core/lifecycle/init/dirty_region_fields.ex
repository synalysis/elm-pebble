defmodule Elmc.Backend.Pebble.SourceWriter.DispatchCore.Lifecycle.Init.DirtyRegionFields do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if ELMC_PEBBLE_DIRTY_REGION_ENABLED
      app->prev_scene.bytes = NULL;
      app->prev_scene.byte_count = 0;
      app->prev_scene.byte_capacity = 0;
      app->prev_scene.command_count = 0;
      app->prev_scene.hash = 0;
      app->prev_scene.dirty = 1;
      app->dirty_rect.x = 0;
      app->dirty_rect.y = 0;
      app->dirty_rect.w = 0;
      app->dirty_rect.h = 0;
      app->dirty_rect_valid = 0;
      app->dirty_rect_full = 1;
    #endif
    """
  end
end
