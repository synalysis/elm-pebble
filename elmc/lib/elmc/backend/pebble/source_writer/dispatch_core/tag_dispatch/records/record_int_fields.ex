defmodule Elmc.Backend.Pebble.SourceWriter.DispatchCore.TagDispatch.Records.RecordIntFields do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.DispatchCore.TagDispatch.Records.RecordIntFields.{
    BuildDispatch,
    Cleanup,
    ValidateAlloc
  }

  @spec body() :: Types.c_source()
  def body do
    [ValidateAlloc.body(), BuildDispatch.body(), Cleanup.body()]
    |> IO.iodata_to_binary()
  end
end
