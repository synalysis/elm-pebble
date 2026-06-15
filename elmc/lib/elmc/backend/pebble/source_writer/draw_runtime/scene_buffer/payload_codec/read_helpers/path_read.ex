defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.ReadHelpers.PathRead do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.ReadHelpers.PathRead.{
    FullI32s,
    IsPathKind,
    PathTail
  }

  @spec body() :: Types.c_source()
  def body do
    [IsPathKind.body(), FullI32s.body(), PathTail.body()]
    |> IO.iodata_to_binary()
  end
end
