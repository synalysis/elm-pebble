defmodule Elmc.Backend.Pebble.SourceWriter.ViewRuntime.ViewCommands do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SourceWriter.ViewRuntime.ViewCommands.{
    Preamble,
    ResultFetch,
    VirtualEmit
  }

  @spec body(Types.view_command_bindings()) :: Types.c_source()
  def body(%{} = bindings) do
    [
      Preamble.body(),
      ResultFetch.body(bindings),
      VirtualEmit.body()
    ]
    |> IO.iodata_to_binary()
  end
end
