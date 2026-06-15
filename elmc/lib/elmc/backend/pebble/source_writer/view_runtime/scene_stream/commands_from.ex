defmodule Elmc.Backend.Pebble.SourceWriter.ViewRuntime.SceneStream.CommandsFrom do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    int elmc_pebble_scene_commands_from(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds, int skip) {
      ELMC_PEBBLE_GENERATED_TRACE_ENTER("elmc_pebble_scene_commands_from");
      if (!app || !out_cmds || max_cmds <= 0 || skip < 0) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_scene_commands_from", -1);
    #if !ELMC_PEBBLE_SCENE_CACHE_ENABLED
      int direct_count = elmc_pebble_view_commands_raw_impl(app, out_cmds, max_cmds, skip, 0, NULL);
      ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_scene_commands_from", direct_count);
    #endif
      int rc = elmc_pebble_ensure_scene(app);
      if (rc != 0) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_scene_commands_from", rc);
      int count = elmc_pebble_scene_decode_from(app, out_cmds, max_cmds, skip, NULL);
      if (count < 0) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_scene_commands_from", count);
      ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_scene_commands_from", count);
    }

"""
  end
end
