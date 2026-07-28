defmodule Elmc.Backend.Pebble.SourceWriter.AppLifecycle do
  @moduledoc false
  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SourceWriter.AppLifecycle.{Deinit, Runtime}

  @spec body(Types.source_bindings()) :: Types.c_source()
  def body(%{} = _bindings) do
    [Runtime.body(), Deinit.body()]
    |> IO.iodata_to_binary()
  end
end
