defmodule Elmc.Backend.Pebble.SourceWriter.ViewRuntime.SceneQuery do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.ViewRuntime.SceneQuery.{
    CommandCount,
    DirtyRect,
    SceneDecodeFrom
  }

  @spec body() :: Types.c_source()
  def body do
    [CommandCount.body(), DirtyRect.body(), SceneDecodeFrom.body()]
    |> IO.iodata_to_binary()
  end
end
