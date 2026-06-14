defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.ReadHelpers.TextRead do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if ELMC_PEBBLE_FEATURE_DRAW_TEXT || ELMC_PEBBLE_FEATURE_DRAW_TEXT_LABEL
    static int elmc_scene_read_text_tail(
        const unsigned char *bytes,
        int *offset,
        int payload_end,
        ElmcPebbleDrawCmd *out_cmd) {
      if (*offset >= payload_end) return 0;
      int text_len = bytes[*offset];
      *offset += 1;
      if (text_len > (int)sizeof(out_cmd->text) - 1) text_len = (int)sizeof(out_cmd->text) - 1;
      if (*offset + text_len > payload_end) return -3;
      memcpy(out_cmd->text, bytes + *offset, (size_t)text_len);
      out_cmd->text[text_len] = '\\0';
      *offset += text_len;
      return 0;
    }
    #endif

"""
  end
end
