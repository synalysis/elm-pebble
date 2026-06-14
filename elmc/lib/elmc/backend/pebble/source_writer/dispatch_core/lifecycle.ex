defmodule Elmc.Backend.Pebble.SourceWriter.DispatchCore.Lifecycle do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SourceWriter.DispatchCore.Lifecycle.{DispatchHooks, Init}

  @spec body() :: Types.c_source()
  def body do
    [DispatchHooks.body(), Init.body()]
    |> IO.iodata_to_binary()
  end
end
