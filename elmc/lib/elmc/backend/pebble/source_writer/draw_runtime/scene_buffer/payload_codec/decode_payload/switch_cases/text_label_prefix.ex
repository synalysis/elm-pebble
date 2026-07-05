defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.DecodePayload.SwitchCases.TextLabelPrefix do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
      int rc = 0;
      /* Compact text-label payloads (8 + 1 + text_len) overlap fixed enum
         payload sizes such as ELMC_SCENE_PL_ROUND_U8 (11); decode by kind first. */
    #if ELMC_PEBBLE_FEATURE_DRAW_TEXT_LABEL
      if (kind == ELMC_PEBBLE_DRAW_TEXT_LABEL_WITH_FONT &&
          payload_len >= ELMC_SCENE_PL_TEXT_LABEL_BASE + 1) {
        out_cmd->p0 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
        out_cmd->p1 = elmc_scene_read_i16(bytes, offset, payload_end);
        out_cmd->p2 = elmc_scene_read_i16(bytes, offset, payload_end);
        return elmc_scene_read_text_tail(bytes, offset, payload_end, out_cmd);
      }
    #endif
    """
  end
end
