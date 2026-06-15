defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.DirtyRegion.Compute.HashMatch do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
      if (app->prev_scene.hash == app->scene.hash &&
          app->prev_scene.command_count == app->scene.command_count &&
          app->prev_scene.byte_count == app->scene.byte_count) {
        app->dirty_rect_full = 0;
        app->dirty_rect_valid = 1;
        return;
      }

    """
  end
end
