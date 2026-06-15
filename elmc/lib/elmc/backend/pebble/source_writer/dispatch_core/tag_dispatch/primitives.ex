defmodule Elmc.Backend.Pebble.SourceWriter.DispatchCore.TagDispatch.Primitives do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.DispatchCore.TagDispatch.Primitives.{
    IntDispatch,
    TagPayload,
    TagScalars
  }

  @spec body() :: Types.c_source()
  def body do
    [IntDispatch.body(), TagScalars.body(), TagPayload.body()]
    |> IO.iodata_to_binary()
  end
end
