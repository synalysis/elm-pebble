defmodule Elmc.Backend.Pebble.SourceWriter.ViewRuntime.SceneStream.ViewCommandsImpl do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static int elmc_pebble_view_commands_impl(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds, int skip, int dedupe) {
      if (!app || !app->initialized || !out_cmds || max_cmds <= 0) return -1;
      if (skip < 0) return -1;
    #if !ELMC_PEBBLE_SCENE_CACHE_ENABLED
      return elmc_pebble_view_commands_raw_impl(app, out_cmds, max_cmds, skip, dedupe, NULL);
    #endif
      int rc = elmc_pebble_ensure_scene(app);
      if (rc != 0) return rc;
      if (skip == 0 && dedupe && app->scene.command_count < max_cmds) {
        if (app->has_prev_ui && app->prev_ops_hash == app->scene.hash) {
          return elmc_pebble_scene_commands_from(app, out_cmds, max_cmds, skip);
        }
        app->has_prev_ui = 1;
        app->prev_window_id = 0;
        app->prev_layer_id = 0;
        app->prev_ops_hash = app->scene.hash;
      }
      return elmc_pebble_scene_commands_from(app, out_cmds, max_cmds, skip);
    }
"""
  end
end
