defmodule Elmc.Backend.Pebble.SourceWriter.ViewRuntime.ViewCommands.ResultFetch.StreamViewFetch do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.ViewRuntime.ViewCommands.ResultFetch.StreamViewFetch.{
    CachedResult,
    ElseOpen,
    ModelInvoke,
    ResultShape
  }

  @spec body(Types.view_command_bindings()) :: Types.c_source()
  def body(%{entry_view_fn: entry_view_fn}) do
    [
      ElseOpen.body(),
      CachedResult.body(),
      ModelInvoke.body(entry_view_fn),
      ResultShape.body()
    ]
    |> IO.iodata_to_binary()
  end
end
