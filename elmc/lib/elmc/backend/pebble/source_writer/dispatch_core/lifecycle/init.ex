defmodule Elmc.Backend.Pebble.SourceWriter.DispatchCore.Lifecycle.Init do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.DispatchCore.Lifecycle.Init.{
    DirtyRegionFields,
    EntryWrappers,
    SceneFields,
    WorkerBootstrap
  }

  @spec body() :: Types.c_source()
  def body do
    [
      EntryWrappers.body(),
      SceneFields.body(),
      DirtyRegionFields.body(),
      WorkerBootstrap.body()
    ]
    |> IO.iodata_to_binary()
  end
end
