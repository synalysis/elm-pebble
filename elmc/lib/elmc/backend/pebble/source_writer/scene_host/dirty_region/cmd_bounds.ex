defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.DirtyRegion.CmdBounds do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SourceWriter.SceneHost.DirtyRegion.CmdBounds.{IsVisual, RequiresFullDirty, VisualBounds}

  @spec body() :: Types.c_source()
  def body do
    [VisualBounds.body(), IsVisual.body(), RequiresFullDirty.body()]
    |> IO.iodata_to_binary()
  end
end
