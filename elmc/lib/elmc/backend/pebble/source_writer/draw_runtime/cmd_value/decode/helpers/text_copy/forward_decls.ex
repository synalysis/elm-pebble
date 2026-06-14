defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Decode.Helpers.TextCopy.ForwardDecls do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        #if !defined(ELMC_HAVE_DIRECT_COMMANDS_MAIN_VIEW)
        #if ELMC_PEBBLE_FEATURE_DRAW_PATH
        static int elmc_decode_path_payload(ElmcValue *payload, ElmcPebbleDrawCmd *out_cmd);
        #endif

    """
  end
end
