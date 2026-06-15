defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.WindowDrawEmit.SimpleDraw do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
      if (elmc_draw_cmd_from_value(value, &cmd) == 0) {
        elmc_emit_draw_cmd(&cmd, out_cmds, max_cmds, count, emitted, skip);
      }
      return 0;
    }
    #endif
"""
  end
end
