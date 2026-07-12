defmodule Elmc.Backend.Pebble.SourceWriter.ViewRuntime.SceneQuery.CommandCount do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body(Types.c_symbol()) :: Types.c_source()
  def body(_entry_view_scene_append) do
    """
    int elmc_pebble_scene_command_count(ElmcPebbleApp *app) {
    #if ELMC_PEBBLE_SCENE_STREAM_CMDS
      int count = elmc_pebble_stream_view_cmds(app, NULL, 0, 0, NULL);
      return count < 0 ? 0 : count;
    #else
      if (elmc_pebble_ensure_scene(app) != 0) return 0;
      return app->scene.command_count;
    #endif
    }

    """
  end
end
