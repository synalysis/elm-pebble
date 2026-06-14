defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Decode.Helpers.TextCopy.CopyDrawText.GuardOpen do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        #if ELMC_PEBBLE_FEATURE_DRAW_TEXT || ELMC_PEBBLE_FEATURE_DRAW_TEXT_LABEL
        static int elmc_copy_draw_text_value(ElmcValue *value, char *out_text, size_t out_size) {
          if (!out_text || out_size == 0) return -1;
          out_text[0] = '\\0';
          if (!value) return -1;
"""
  end
end
