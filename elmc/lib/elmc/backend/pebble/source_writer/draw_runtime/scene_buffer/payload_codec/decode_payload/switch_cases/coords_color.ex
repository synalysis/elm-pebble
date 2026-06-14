defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.DecodePayload.SwitchCases.CoordsColor do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
      case ELMC_SCENE_PL_COORDS_COLOR_U8:
        rc = elmc_scene_read_coords_i16(bytes, offset, payload_end, out_cmd); if (rc != 0) return rc;
        if (*offset >= payload_end) return -3;
        out_cmd->p4 = bytes[*offset];
        *offset += 1;
        return 0;
      case ELMC_SCENE_PL_COORDS_COLOR_I32:
    #if ELMC_PEBBLE_FEATURE_DRAW_TEXT_INT
        if (kind == ELMC_PEBBLE_DRAW_TEXT_INT_WITH_FONT) {
          out_cmd->p0 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
          out_cmd->p1 = elmc_scene_read_i16(bytes, offset, payload_end);
          out_cmd->p2 = elmc_scene_read_i16(bytes, offset, payload_end);
          out_cmd->p3 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
          return 0;
        }
    #endif
        rc = elmc_scene_read_coords_i16(bytes, offset, payload_end, out_cmd); if (rc != 0) return rc;
        out_cmd->p4 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
        return 0;
    """
  end
end
