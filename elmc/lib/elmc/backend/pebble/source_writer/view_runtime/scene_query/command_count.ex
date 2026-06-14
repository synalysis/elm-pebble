defmodule Elmc.Backend.Pebble.SourceWriter.ViewRuntime.SceneQuery.CommandCount do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    int elmc_pebble_scene_command_count(ElmcPebbleApp *app) {
      if (elmc_pebble_ensure_scene(app) != 0) return 0;
      return app->scene.command_count;
    }

    """
  end
end
