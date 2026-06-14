defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.DecodePayload.Fallbacks.TextDraw do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if ELMC_PEBBLE_FEATURE_DRAW_TEXT
      if (payload_len >= ELMC_SCENE_PL_TEXT_BASE &&
          kind == ELMC_PEBBLE_DRAW_TEXT &&
          payload_len >= ELMC_SCENE_PL_TEXT_BASE + 1) {
        rc = elmc_scene_read_text_bounds_i16(bytes, offset, payload_end, out_cmd); if (rc != 0) return rc;
        out_cmd->p0 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
        out_cmd->p5 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
        return elmc_scene_read_text_tail(bytes, offset, payload_end, out_cmd);
      }
    #endif
    """
  end
end
