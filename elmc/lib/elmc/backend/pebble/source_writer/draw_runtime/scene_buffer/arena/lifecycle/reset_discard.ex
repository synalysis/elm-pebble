defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.Lifecycle.ResetDiscard do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static void elmc_pebble_scene_reset(ElmcPebbleApp *app) {
      if (!app) return;
      app->scene.byte_count = 0;
      app->scene.command_count = 0;
      app->scene.hash = 1469598103934665603ULL;
    }

    static void elmc_pebble_scene_discard_build(ElmcPebbleApp *app) {
      if (!app) return;
      app->scene.byte_count = 0;
      app->scene.command_count = 0;
      app->scene.dirty = 1;
    }

"""
  end
end
