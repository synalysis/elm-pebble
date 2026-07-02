defmodule Elmc.Backend.Pebble.SourceWriter.ViewRuntime.SceneBuild.AppendFallbackBuild do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SourceWriter.ViewRuntime.SceneBuild.DirectBuild

  @spec body(Types.scene_build_bindings(), Types.c_macro_name()) :: Types.c_source()
  def body(%{entry_view_scene_append: _} = bindings, direct_view_macro) do
    inner =
      DirectBuild.body(bindings)
      |> String.replace_prefix("#if defined(ELMC_PEBBLE_DIRECT_VIEW_SCENE)", "")
      |> String.trim_leading()

    """
    #elif defined(#{direct_view_macro}) && !defined(ELMC_PEBBLE_DIRECT_VIEW_SCENE)
    #{inner}
    """
  end
end
