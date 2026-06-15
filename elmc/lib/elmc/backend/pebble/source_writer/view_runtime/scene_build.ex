defmodule Elmc.Backend.Pebble.SourceWriter.ViewRuntime.SceneBuild do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.ViewRuntime.SceneBuild.{
    ChunkBuild,
    ClearCache,
    DirectBuild,
    EnsureFinish,
    EnsurePreamble
  }

  @spec body(Types.scene_build_bindings()) :: Types.c_source()
  def body(%{entry_view_scene_append: _} = bindings) do
    [
      ClearCache.body(),
      EnsurePreamble.body(),
      DirectBuild.body(bindings),
      ChunkBuild.body(),
      EnsureFinish.body()
    ]
    |> IO.iodata_to_binary()
  end
end
