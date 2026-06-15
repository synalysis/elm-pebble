defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.DecodePayload.SwitchCases.Pixel do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if ELMC_PEBBLE_FEATURE_DRAW_PIXEL
      case ELMC_SCENE_PL_PIXEL:
        out_cmd->p0 = elmc_scene_read_i16(bytes, offset, payload_end);
        out_cmd->p1 = elmc_scene_read_i16(bytes, offset, payload_end);
        if (*offset >= payload_end) return -3;
        out_cmd->p2 = bytes[*offset];
        *offset += 1;
        return 0;
    #endif
    """
  end
end
