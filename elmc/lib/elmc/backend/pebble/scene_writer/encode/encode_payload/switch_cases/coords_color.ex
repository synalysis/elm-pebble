defmodule Elmc.Backend.Pebble.SceneWriter.Encode.EncodePayload.SwitchCases.CoordsColor do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
          case ELMC_SCENE_PL_COORDS_COLOR_U8:
            rc = elmc_scene_writer_write_coords_i16(writer, cmd); if (rc != 0) return rc;
            return elmc_scene_writer_put_u8(writer, (unsigned char)cmd->p4);
          case ELMC_SCENE_PL_COORDS_COLOR_I32:
        #if ELMC_PEBBLE_FEATURE_DRAW_TEXT_INT
            if (cmd->kind == ELMC_PEBBLE_DRAW_TEXT_INT_WITH_FONT) {
              rc = elmc_scene_writer_put_i32(writer, cmd->p0); if (rc != 0) return rc;
              rc = elmc_scene_writer_put_i16(writer, cmd->p1); if (rc != 0) return rc;
              rc = elmc_scene_writer_put_i16(writer, cmd->p2); if (rc != 0) return rc;
              return elmc_scene_writer_put_i32(writer, cmd->p3);
            }
        #endif
            rc = elmc_scene_writer_write_coords_i16(writer, cmd); if (rc != 0) return rc;
            return elmc_scene_writer_put_i32(writer, cmd->p4);
    """
  end
end
