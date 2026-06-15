defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.Lifecycle do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.Lifecycle.{
    BufferFree,
    RebuildInvalidate,
    ResetDiscard
  }

  @spec body() :: Types.c_source()
  def body do
    [ResetDiscard.body(), BufferFree.body(), RebuildInvalidate.body()]
    |> IO.iodata_to_binary()
  end
end
