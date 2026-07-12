defmodule Elmc.Backend.Pebble.SceneWriter.HeaderLate.DecodeDecl do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if !ELMC_PEBBLE_SCENE_STREAM_CMDS
    int elmc_pebble_scene_decode_record(
        const unsigned char *bytes,
        int byte_count,
        int *offset,
        ElmcPebbleDrawCmd *out_cmd);
    #endif
    """
  end
end
