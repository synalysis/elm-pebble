defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.Lifecycle.RebuildInvalidate.MarkDirty do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static void elmc_pebble_mark_scene_dirty(ElmcPebbleApp *app) {
      if (!app) return;
      app->scene.dirty = 1;
    }

    """
  end
end
