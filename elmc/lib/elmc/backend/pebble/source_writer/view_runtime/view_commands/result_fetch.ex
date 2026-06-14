defmodule Elmc.Backend.Pebble.SourceWriter.ViewRuntime.ViewCommands.ResultFetch do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.ViewRuntime.ViewCommands.ResultFetch.{
    DirectViewFetch,
    ModelOnlyFetch,
    StreamViewFetch
  }

  @spec body(Types.view_command_bindings()) :: Types.c_source()
  def body(%{has_view: true} = bindings) do
    [DirectViewFetch.body(), StreamViewFetch.body(bindings)]
    |> IO.iodata_to_binary()
  end

  def body(_bindings) do
    ModelOnlyFetch.body()
  end
end
