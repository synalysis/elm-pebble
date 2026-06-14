defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.WindowDrawEmit do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.SceneHost.WindowDrawEmit.{
    ContextGroup,
    EmitHelper,
    SimpleDraw
  }

  @spec body() :: Types.c_source()
  def body do
    [EmitHelper.body(), ContextGroup.body(), SimpleDraw.body()]
    |> IO.iodata_to_binary()
  end
end
