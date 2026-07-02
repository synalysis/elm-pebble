defmodule Elmc.Backend.Pebble.SourceWriter.ViewRuntime.ViewCommands.ResultFetch.DirectViewFetch do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body(Types.view_command_bindings()) :: Types.c_source()
  def body(%{direct_view_macro: direct_view_macro}) do
    """
      #if defined(ELMC_PEBBLE_DIRECT_VIEW_SCENE) || defined(#{direct_view_macro})
            int direct_rc = elmc_pebble_ensure_scene(app);
            if (direct_rc != 0) return direct_rc;
            if (skip == 0 && dedupe && app->scene.command_count < max_cmds) {
              if (app->has_prev_ui && app->prev_ops_hash == app->scene.hash) {
                return 0;
              }
              app->has_prev_ui = 1;
              app->prev_window_id = 0;
              app->prev_layer_id = 0;
              app->prev_ops_hash = app->scene.hash;
            }
            return elmc_pebble_scene_decode_from(app, out_cmds, max_cmds, skip, out_emitted_end);
    """
  end
end
