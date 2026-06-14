defmodule Elmc.Backend.Pebble.SourceWriter.DispatchCore.TagDispatch do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SourceWriter.DispatchCore.TagDispatch.{Primitives, Records}

  @spec body() :: Types.c_source()
  def body do
    [Primitives.body(), Records.body()]
    |> IO.iodata_to_binary()
  end
end
