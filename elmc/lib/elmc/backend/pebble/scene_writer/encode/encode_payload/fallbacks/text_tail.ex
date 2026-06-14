defmodule Elmc.Backend.Pebble.SceneWriter.Encode.EncodePayload.Fallbacks.TextTail do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        #if ELMC_PEBBLE_FEATURE_DRAW_TEXT || ELMC_PEBBLE_FEATURE_DRAW_TEXT_LABEL
          if (payload_len > ELMC_SCENE_PL_FULL &&
              (cmd->kind == ELMC_PEBBLE_DRAW_TEXT ||
               cmd->kind == ELMC_PEBBLE_DRAW_TEXT_LABEL_WITH_FONT)) {
            rc = elmc_scene_writer_put_i32(writer, cmd->p0); if (rc != 0) return rc;
            rc = elmc_scene_writer_put_i32(writer, cmd->p1); if (rc != 0) return rc;
            rc = elmc_scene_writer_put_i32(writer, cmd->p2); if (rc != 0) return rc;
            rc = elmc_scene_writer_put_i32(writer, cmd->p3); if (rc != 0) return rc;
            rc = elmc_scene_writer_put_i32(writer, cmd->p4); if (rc != 0) return rc;
            rc = elmc_scene_writer_put_i32(writer, cmd->p5); if (rc != 0) return rc;
            return elmc_scene_writer_write_text_tail(writer, cmd);
          }
        #endif
    """
  end
end
