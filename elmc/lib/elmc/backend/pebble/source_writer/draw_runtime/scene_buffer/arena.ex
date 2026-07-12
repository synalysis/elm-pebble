defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.{Chunks, Lifecycle, Pool, ReservePut, StaticCapacity, ValueHelpers}

  @spec body() :: Types.c_source()
  def body do
    """
    #{Pool.body()}
    #if !ELMC_PEBBLE_SCENE_STREAM_CMDS
    #{StaticCapacity.body()}
    #{Chunks.body()}
    #{ReservePut.body()}
    #{ValueHelpers.body()}
    #endif
    #{Lifecycle.body()}
    """
  end
end
