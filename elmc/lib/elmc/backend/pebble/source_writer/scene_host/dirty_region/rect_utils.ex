defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.DirtyRegion.RectUtils do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.SceneHost.DirtyRegion.RectUtils.{
    NextRecord,
    RectOps
  }

  @spec body() :: Types.c_source()
  def body do
    [NextRecord.body(), RectOps.body()]
    |> IO.iodata_to_binary()
  end
end
