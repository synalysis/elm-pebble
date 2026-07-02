defmodule Elmc.Backend.Pebble.SourceWriter.ViewRuntime.SceneBuild do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.ViewRuntime.SceneBuild.{
    AppendFallbackBuild,
    ChunkBuild,
    ClearCache,
    DirectBuild,
    EnsureFinish,
    EnsurePreamble
  }

  @spec body(Types.scene_build_bindings()) :: Types.c_source()
  def body(%{direct_view_macro: direct_view_macro} = bindings) do
    [
      ClearCache.body(),
      EnsurePreamble.body(),
      DirectBuild.body(bindings),
      AppendFallbackBuild.body(bindings, direct_view_macro),
      ChunkBuild.body(),
      EnsureFinish.body()
    ]
    |> IO.iodata_to_binary()
  end
end
