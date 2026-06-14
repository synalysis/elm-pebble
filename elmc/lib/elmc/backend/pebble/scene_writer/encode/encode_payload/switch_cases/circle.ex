defmodule Elmc.Backend.Pebble.SceneWriter.Encode.EncodePayload.SwitchCases.Circle do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        #if ELMC_PEBBLE_FEATURE_DRAW_CIRCLE || ELMC_PEBBLE_FEATURE_DRAW_FILL_CIRCLE
          case ELMC_SCENE_PL_CIRCLE_U8:
            rc = elmc_scene_writer_put_i16(writer, cmd->p0); if (rc != 0) return rc;
            rc = elmc_scene_writer_put_i16(writer, cmd->p1); if (rc != 0) return rc;
            rc = elmc_scene_writer_put_i16(writer, cmd->p2); if (rc != 0) return rc;
            return elmc_scene_writer_put_u8(writer, (unsigned char)cmd->p3);
          case ELMC_SCENE_PL_CIRCLE_I32:
            rc = elmc_scene_writer_put_i16(writer, cmd->p0); if (rc != 0) return rc;
            rc = elmc_scene_writer_put_i16(writer, cmd->p1); if (rc != 0) return rc;
            rc = elmc_scene_writer_put_i16(writer, cmd->p2); if (rc != 0) return rc;
            return elmc_scene_writer_put_i32(writer, cmd->p3);
        #endif
    """
  end
end
