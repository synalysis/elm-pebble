defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.{Chunks, Lifecycle, ReservePut, StaticCapacity, ValueHelpers}

  @spec body() :: Types.c_source()
  def body do
    [
      StaticCapacity.body(),
      Chunks.body(),
      Lifecycle.body(),
      ReservePut.body(),
      ValueHelpers.body()
    ]
    |> IO.iodata_to_binary()
  end
end
