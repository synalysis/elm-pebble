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
    [
      SceneBuild.body(bindings),
      SceneQuery.body(),
      SceneStream.body(),
      ViewCommands.body(bindings)
    ]
    |> IO.iodata_to_binary()
  end
end
