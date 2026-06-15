defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.ReadHelpers do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.ReadHelpers.{
    CoordsRead,
    PathRead,
    TextRead
  }

  @spec body() :: Types.c_source()
  def body do
    [TextRead.body(), CoordsRead.body(), PathRead.body()]
    |> IO.iodata_to_binary()
  end
end
