defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.DecodePayload.Fallbacks.TextTail do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if ELMC_PEBBLE_FEATURE_DRAW_TEXT || ELMC_PEBBLE_FEATURE_DRAW_TEXT_LABEL
      if (payload_len > ELMC_SCENE_PL_FULL &&
          (kind == ELMC_PEBBLE_DRAW_TEXT ||
           kind == ELMC_PEBBLE_DRAW_TEXT_LABEL_WITH_FONT)) {
        out_cmd->p0 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
        out_cmd->p1 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
        out_cmd->p2 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
        out_cmd->p3 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
        out_cmd->p4 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
        out_cmd->p5 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
        return elmc_scene_read_text_tail(bytes, offset, payload_end, out_cmd);
      }
    #endif
    """
  end
end
