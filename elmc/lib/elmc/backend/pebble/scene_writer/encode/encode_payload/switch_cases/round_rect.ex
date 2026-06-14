defmodule Elmc.Backend.Pebble.SceneWriter.Encode.EncodePayload.SwitchCases.RoundRect do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        #if ELMC_PEBBLE_FEATURE_DRAW_ROUND_RECT
          case ELMC_SCENE_PL_ROUND_U8:
            rc = elmc_scene_writer_write_coords_i16(writer, cmd); if (rc != 0) return rc;
            rc = elmc_scene_writer_put_i16(writer, cmd->p4); if (rc != 0) return rc;
            return elmc_scene_writer_put_u8(writer, (unsigned char)cmd->p5);
          case ELMC_SCENE_PL_ROUND_I32:
            rc = elmc_scene_writer_write_coords_i16(writer, cmd); if (rc != 0) return rc;
            rc = elmc_scene_writer_put_i16(writer, cmd->p4); if (rc != 0) return rc;
            return elmc_scene_writer_put_i32(writer, cmd->p5);
        #endif
    """
  end
end
