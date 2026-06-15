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
    [WriterPut.body(), TextWrite.body(), CoordsFull.body(), PathWrite.body()]
    |> IO.iodata_to_binary()
  end
end
