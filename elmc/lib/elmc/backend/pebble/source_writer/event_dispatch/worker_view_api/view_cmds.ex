defmodule Elmc.Backend.Pebble.SourceWriter.EventDispatch.WorkerViewApi.ViewCmds do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static int elmc_pebble_view_commands_impl(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds, int skip, int dedupe);
    static int elmc_pebble_view_commands_raw_impl(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds, int skip, int dedupe, int *out_emitted_end);

    int elmc_pebble_view_command(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmd) {
      int count = elmc_pebble_view_commands(app, out_cmd, 1);
      if (count < 0) return count;
      if (count == 0) return -7;
      return 0;
    }

    int elmc_pebble_view_commands(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds) {
      return elmc_pebble_view_commands_impl(app, out_cmds, max_cmds, 0, 1);
    }

    int elmc_pebble_view_commands_from(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds, int skip) {
      int count = elmc_pebble_view_commands_raw_impl(app, out_cmds, max_cmds, skip, 0, NULL);
      if (count < max_cmds) {
        elmc_pebble_clear_view_cache(app);
      }
      return count;
    }
"""
  end
end
