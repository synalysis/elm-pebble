defmodule Elmc.Backend.Pebble.SourceWriter.ViewRuntime.SceneStream do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.ViewRuntime.SceneStream.{
    CommandsFrom,
    CommandsNext,
    ResetCursor,
    StreamViewCmds,
    ViewCommandsImpl
  }

  @spec body(Types.c_symbol()) :: Types.c_source()
  def body(entry_view_scene_append) do
    [
      StreamViewCmds.body(entry_view_scene_append),
      ResetCursor.body(),
      CommandsNext.body(entry_view_scene_append),
      CommandsFrom.body(),
      ViewCommandsImpl.body()
    ]
    |> IO.iodata_to_binary()
  end
end
