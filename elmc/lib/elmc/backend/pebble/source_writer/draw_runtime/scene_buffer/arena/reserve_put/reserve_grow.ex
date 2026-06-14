defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.ReservePut.ReserveGrow do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.ReservePut.ReserveGrow.{
    Reserve,
    ReserveCapacity,
    TrimCapacity
  }

  @spec body() :: Types.c_source()
  def body do
    [ReserveCapacity.body(), TrimCapacity.body(), Reserve.body()]
    |> IO.iodata_to_binary()
  end
end
