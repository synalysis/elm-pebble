defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.ReservePut do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.ReservePut.{PutBytes, ReserveGrow}

  @spec body() :: Types.c_source()
  def body do
    [ReserveGrow.body(), PutBytes.body()]
    |> IO.iodata_to_binary()
  end
end
