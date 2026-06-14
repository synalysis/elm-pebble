defmodule Elmc.Backend.Pebble.SourceWriter.ViewRuntime.ViewCommands.VirtualEmit do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.ViewRuntime.ViewCommands.VirtualEmit.{
    DedupeAndFinish,
    DirectStub,
    ExtractAndWalk
  }

  @spec body() :: Types.c_source()
  def body do
    [ExtractAndWalk.body(), DedupeAndFinish.body(), DirectStub.body()]
    |> IO.iodata_to_binary()
  end
end
