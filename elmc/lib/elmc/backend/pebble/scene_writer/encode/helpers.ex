defmodule Elmc.Backend.Pebble.SceneWriter.Encode.Helpers do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SceneWriter.Encode.Helpers.{
    CoordsFull,
    PathWrite,
    TextWrite,
    WriterPut
  }

  @spec body() :: Types.c_source()
  def body do
    """
    #if ELMC_PEBBLE_SCENE_STREAM_CMDS
    #{WriterPut.stream_body()}
    #else
    #{WriterPut.body()}
    #{TextWrite.body()}
    #{CoordsFull.body()}
    #{PathWrite.body()}
    #endif
    """
  end
end
