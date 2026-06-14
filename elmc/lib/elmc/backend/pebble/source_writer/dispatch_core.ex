defmodule Elmc.Backend.Pebble.SourceWriter.DispatchCore do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SourceWriter.DispatchCore.{Lifecycle, TagDispatch}

  @spec body() :: Types.c_source()
  def body do
    [Lifecycle.body(), TagDispatch.body()]
    |> IO.iodata_to_binary()
  end
end
