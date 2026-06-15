defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.DirtyRegion.Compute.RecordDiff do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.SceneHost.DirtyRegion.Compute.RecordDiff.{
    Finish,
    Iteration,
    Preamble
  }

  @spec body() :: Types.c_source()
  def body do
    [Preamble.body(), Iteration.body(), Finish.body()]
    |> IO.iodata_to_binary()
  end
end
