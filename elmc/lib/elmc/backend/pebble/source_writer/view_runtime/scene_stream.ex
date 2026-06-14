defmodule Elmc.Backend.Pebble.SourceWriter.ViewRuntime.SceneStream do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.ViewRuntime.SceneStream.{
    CommandsFrom,
    CommandsNext,
    ResetCursor,
    ViewCommandsImpl
  }

  @spec body() :: Types.c_source()
  def body do
    [
      ResetCursor.body(),
      CommandsNext.body(),
      CommandsFrom.body(),
      ViewCommandsImpl.body()
    ]
    |> IO.iodata_to_binary()
  end
end
