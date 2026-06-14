defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Decode.Helpers.TextCopy.CopyDrawText.StringPath do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
          if (value->tag == ELMC_TAG_STRING && value->payload != NULL) {
            strncpy(out_text, (const char *)value->payload, out_size - 1);
            out_text[out_size - 1] = '\\0';
            return 0;
          }
          if (value->tag != ELMC_TAG_LIST) return -1;
"""
  end
end
