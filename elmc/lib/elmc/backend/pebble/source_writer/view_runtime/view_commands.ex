defmodule Elmc.Backend.Pebble.SourceWriter.ViewRuntime.ViewCommands do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SourceWriter.ViewRuntime.ViewCommands.{
    Preamble,
    ResultFetch,
    VirtualEmit
  }

  @spec body(Types.source_bindings()) :: Types.c_source()
  def body(%{} = bindings) do
    view_bindings = %{
      entry_view_fn: bindings.entry_view_fn,
      has_view: bindings.has_view
    }

    [
      Preamble.body(),
      ResultFetch.body(view_bindings),
      VirtualEmit.body()
    ]
    |> IO.iodata_to_binary()
  end
end
