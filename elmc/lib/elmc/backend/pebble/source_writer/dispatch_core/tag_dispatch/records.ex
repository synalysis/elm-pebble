defmodule Elmc.Backend.Pebble.SourceWriter.DispatchCore.TagDispatch.Records do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.DispatchCore.TagDispatch.Records.{
    IntTuple,
    IntValuesDispatch,
    RecordIntFields
  }

  @spec body() :: Types.c_source()
  def body do
    [IntTuple.body(), IntValuesDispatch.body(), RecordIntFields.body()]
    |> IO.iodata_to_binary()
  end
end
