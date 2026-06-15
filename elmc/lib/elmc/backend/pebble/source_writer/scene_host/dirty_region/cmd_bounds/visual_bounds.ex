defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.DirtyRegion.CmdBounds.VisualBounds do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.SceneHost.DirtyRegion.CmdBounds.VisualBounds.{
    CircleDefault,
    PixelLine,
    RectFamily
  }

  @spec body() :: Types.c_source()
  def body do
    [PixelLine.body(), RectFamily.body(), CircleDefault.body()]
    |> IO.iodata_to_binary()
  end
end
