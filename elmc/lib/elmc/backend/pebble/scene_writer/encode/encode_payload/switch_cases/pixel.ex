defmodule Elmc.Backend.Pebble.SceneWriter.Encode.EncodePayload.SwitchCases.Pixel do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        #if ELMC_PEBBLE_FEATURE_DRAW_PIXEL
          case ELMC_SCENE_PL_PIXEL:
            rc = elmc_scene_writer_put_i16(writer, cmd->p0); if (rc != 0) return rc;
            rc = elmc_scene_writer_put_i16(writer, cmd->p1); if (rc != 0) return rc;
            return elmc_scene_writer_put_u8(writer, (unsigned char)cmd->p2);
        #endif
    """
  end
end
