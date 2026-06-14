defmodule Elmc.Backend.Pebble.SourceWriter.EventDispatch.TagCallbacks do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SourceWriter.EventDispatch.TagCallbacks.{CompassEmbed, StorageRandom}

  @spec body(Types.event_dispatch_bindings()) :: Types.c_source()
  def body(%{} = bindings) do
    [
      StorageRandom.body(bindings),
      CompassEmbed.body(bindings)
    ]
    |> IO.iodata_to_binary()
  end
end
