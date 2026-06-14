defmodule Elmc.Backend.Pebble.SceneWriter.Encode.EncodePayload.Fallbacks.TextDraw do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        #if ELMC_PEBBLE_FEATURE_DRAW_TEXT
          if (payload_len >= ELMC_SCENE_PL_TEXT_BASE &&
              cmd->kind == ELMC_PEBBLE_DRAW_TEXT &&
              payload_len == ELMC_SCENE_PL_TEXT_BASE + 1 + elmc_scene_text_len(cmd)) {
            int rc2 = elmc_scene_writer_write_text_bounds_i16(writer, cmd); if (rc2 != 0) return rc2;
            rc2 = elmc_scene_writer_put_i32(writer, cmd->p0); if (rc2 != 0) return rc2;
            rc2 = elmc_scene_writer_put_i32(writer, cmd->p5); if (rc2 != 0) return rc2;
            return elmc_scene_writer_write_text_tail(writer, cmd);
          }
        #endif
    """
  end
end
