defmodule Elmc.Backend.Pebble.SourceWriter.AppLifecycle do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SourceWriter.AppLifecycle.{Deinit, Runtime, Tick}

  @spec body(Types.source_bindings()) :: Types.c_source()
  def body(%{} = bindings) do
    lifecycle_bindings = %{msg: bindings.msg}

    [
      Tick.body(lifecycle_bindings),
      Runtime.body(),
      Deinit.body()
    ]
    |> IO.iodata_to_binary()
  end
end
