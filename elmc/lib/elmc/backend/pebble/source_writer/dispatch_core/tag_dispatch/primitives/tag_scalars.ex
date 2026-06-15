defmodule Elmc.Backend.Pebble.SourceWriter.DispatchCore.TagDispatch.Primitives.TagScalars do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.DispatchCore.TagDispatch.Primitives.TagScalars.{
    TagBool,
    TagString,
    TagValue
  }

  @spec body() :: Types.c_source()
  def body do
    [TagValue.body(), TagBool.body(), TagString.body()]
    |> IO.iodata_to_binary()
  end
end
