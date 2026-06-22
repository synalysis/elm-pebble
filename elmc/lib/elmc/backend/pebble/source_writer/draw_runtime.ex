defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.{CmdValue, SceneBuffer, VectorSequenceInstances}

  @spec body() :: Types.c_source()
  def body do
    [CmdValue.body(), SceneBuffer.body(), VectorSequenceInstances.body()]
    |> IO.iodata_to_binary()
  end
end
