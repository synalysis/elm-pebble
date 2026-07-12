defmodule Elmc.Backend.Pebble.SceneWriter.Encode do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SceneWriter.Encode.{EncodePayload, Helpers, WriterPush}

  @spec body() :: Types.c_source()
  def body do
    """
    #{Helpers.body()}
    #if !ELMC_PEBBLE_SCENE_STREAM_CMDS
    #{EncodePayload.body()}
    #endif
    #{WriterPush.body()}
    """
  end
end
