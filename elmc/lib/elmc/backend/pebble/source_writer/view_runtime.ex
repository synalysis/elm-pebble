defmodule Elmc.Backend.Pebble.SourceWriter.ViewRuntime do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SourceWriter.ViewRuntime.{
    SceneBuild,
    SceneQuery,
    SceneStream,
    ViewCommands
  }

  @spec body(Types.source_bindings()) :: Types.c_source()
  def body(%{} = bindings) do
    scene_build_bindings = %{
      entry_view_scene_append: bindings.entry_view_scene_append,
      direct_view_macro: bindings.direct_view_macro,
      append_fallback_enabled?: Map.get(bindings, :append_fallback_enabled?, false)
    }

    view_command_bindings = %{
      entry_view_fn: bindings.entry_view_fn,
      has_view: bindings.has_view,
      direct_view_macro: bindings.direct_view_macro,
      entry_view_direct_abi?: Map.get(bindings, :entry_view_direct_abi?, false)
    }

    [
      SceneBuild.body(scene_build_bindings),
      SceneQuery.body(),
      SceneStream.body(),
      ViewCommands.body(view_command_bindings)
    ]
    |> IO.iodata_to_binary()
  end
end
