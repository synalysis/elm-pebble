defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.Lifecycle.RebuildInvalidate do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.Lifecycle.RebuildInvalidate.{
    DecodeFailure,
    FullDirtyMark,
    InvalidateScene,
    MarkDirty,
    PrepareRebuild
  }

  @spec body() :: Types.c_source()
  def body do
    [
      MarkDirty.body(),
      PrepareRebuild.body(),
      FullDirtyMark.body(),
      InvalidateScene.body(),
      DecodeFailure.body()
    ]
    |> IO.iodata_to_binary()
  end
end
