defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Decode.FromValue.TuplePath do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
            if (out_cmd->kind == ELMC_PEBBLE_DRAW_PATH_FILLED ||
                out_cmd->kind == ELMC_PEBBLE_DRAW_PATH_OUTLINE ||
                out_cmd->kind == ELMC_PEBBLE_DRAW_PATH_OUTLINE_OPEN) {
              return elmc_decode_path_payload(tuple->second, out_cmd);
            }
    #endif
    """
  end
end
