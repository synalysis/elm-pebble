defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.DecodePayload.SwitchCases.FixedScalars do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
      switch (payload_len) {
      case ELMC_SCENE_PL_EMPTY:
        return 0;
      case ELMC_SCENE_PL_U8:
        if (*offset >= payload_end) return -3;
        out_cmd->p0 = bytes[*offset];
        *offset += 1;
        return 0;
      case ELMC_SCENE_PL_I32:
        out_cmd->p0 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
        return 0;
    """
  end
end
