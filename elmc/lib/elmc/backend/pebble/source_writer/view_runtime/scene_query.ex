defmodule Elmc.Backend.Pebble.SourceWriter.ViewRuntime.SceneQuery do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.ViewRuntime.SceneQuery.{
    CommandCount,
    DirtyRect,
    SceneDecodeFrom
  }

  @spec body(Types.c_symbol()) :: Types.c_source()
  def body(entry_view_scene_append) do
    [CommandCount.body(entry_view_scene_append), DirtyRect.body(), SceneDecodeFrom.body()]
    |> IO.iodata_to_binary()
  end
end
