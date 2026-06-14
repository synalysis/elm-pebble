defmodule Elmc.Backend.Pebble.SourceWriter.EventDispatch do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SourceWriter.EventDispatch.{
    AppMessage,
    SubscriptionEvents,
    TagCallbacks,
    WorkerViewApi
  }

  @spec body(Types.source_bindings()) :: Types.c_source()
  def body(%{} = bindings) do
    event_bindings = %{
      msg: bindings.msg,
      random_generate_tag: bindings.random_generate_tag,
      compass_dispatch_source: bindings.compass_dispatch_source
    }

    [
      AppMessage.body(event_bindings),
      SubscriptionEvents.body(),
      TagCallbacks.body(event_bindings),
      WorkerViewApi.body()
    ]
    |> IO.iodata_to_binary()
  end
end
