defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.ReservePut.PutBytes do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.ReservePut.PutBytes.{
    HashByte,
    PutI16,
    PutI32,
    PutU8
  }

  @spec body() :: Types.c_source()
  def body do
    [HashByte.body(), PutU8.body(), PutI16.body(), PutI32.body()]
    |> IO.iodata_to_binary()
  end
end
