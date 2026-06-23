defmodule Elmc.Backend.Pebble.HeaderWriter.ApiDecls.ViewSceneApi do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.{
    BitmapSequenceInstances,
    VectorSequenceInstances
  }

  @spec body() :: Types.c_source()
  def body do
    """
    typedef struct GContext GContext;

    int elmc_pebble_take_cmd(ElmcPebbleApp *app, ElmcPebbleCmd *out_cmd);
    int elmc_pebble_view_command(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmd);
    int elmc_pebble_view_commands(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds);
    int elmc_pebble_view_commands_from(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds, int skip);
    int elmc_pebble_scene_commands_from(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds, int skip);
    void elmc_pebble_scene_reset_draw_cursor(ElmcPebbleApp *app);
    int elmc_pebble_scene_commands_next(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds);
    int elmc_pebble_ensure_scene(ElmcPebbleApp *app);
    int elmc_pebble_scene_command_count(ElmcPebbleApp *app);
    int elmc_pebble_scene_dirty_rect(ElmcPebbleApp *app, ElmcPebbleRect *out_rect, int *out_full);
    void elmc_pebble_invalidate_scene(ElmcPebbleApp *app);
    #{VectorSequenceInstances.header_decls()}
    #{BitmapSequenceInstances.header_decls()}
"""
  end
end
