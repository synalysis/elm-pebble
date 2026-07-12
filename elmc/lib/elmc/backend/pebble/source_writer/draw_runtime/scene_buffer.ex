defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.{Arena, PayloadCodec}

  @spec body() :: Types.c_source()
  def body do
    """
    #{Arena.body()}
    #if !ELMC_PEBBLE_SCENE_STREAM_CMDS
    #{PayloadCodec.body()}
    #endif
    """
  end
end
