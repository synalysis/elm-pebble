defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.DecodePayload.SwitchCases.Circle do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if ELMC_PEBBLE_FEATURE_DRAW_CIRCLE || ELMC_PEBBLE_FEATURE_DRAW_FILL_CIRCLE
      case ELMC_SCENE_PL_CIRCLE_U8:
        out_cmd->p0 = elmc_scene_read_i16(bytes, offset, payload_end);
        out_cmd->p1 = elmc_scene_read_i16(bytes, offset, payload_end);
        out_cmd->p2 = elmc_scene_read_i16(bytes, offset, payload_end);
        if (*offset >= payload_end) return -3;
        out_cmd->p3 = bytes[*offset];
        *offset += 1;
        return 0;
      case ELMC_SCENE_PL_CIRCLE_I32:
        out_cmd->p0 = elmc_scene_read_i16(bytes, offset, payload_end);
        out_cmd->p1 = elmc_scene_read_i16(bytes, offset, payload_end);
        out_cmd->p2 = elmc_scene_read_i16(bytes, offset, payload_end);
        out_cmd->p3 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
        return 0;
    #endif
    """
  end
end
