defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.DecodePayload.SwitchCases.RoundRect do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if ELMC_PEBBLE_FEATURE_DRAW_ROUND_RECT
      case ELMC_SCENE_PL_ROUND_U8:
        rc = elmc_scene_read_coords_i16(bytes, offset, payload_end, out_cmd); if (rc != 0) return rc;
        out_cmd->p4 = elmc_scene_read_i16(bytes, offset, payload_end);
        if (*offset >= payload_end) return -3;
        out_cmd->p5 = bytes[*offset];
        *offset += 1;
        return 0;
      case ELMC_SCENE_PL_ROUND_I32:
        rc = elmc_scene_read_coords_i16(bytes, offset, payload_end, out_cmd); if (rc != 0) return rc;
        out_cmd->p4 = elmc_scene_read_i16(bytes, offset, payload_end);
        out_cmd->p5 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
        return 0;
    #endif
    """
  end
end
