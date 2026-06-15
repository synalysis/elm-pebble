defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.DirtyRegion.Compute do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.SceneHost.DirtyRegion.Compute.{
    HashMatch,
    RecordDiff,
    Reset
  }

  @spec body() :: Types.c_source()
  def body do
    [Reset.body(), HashMatch.body(), RecordDiff.body()]
    |> IO.iodata_to_binary()
  end
end
