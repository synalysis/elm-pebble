defmodule Elmc.Backend.Pebble.SourceWriter.EventDispatch.SubscriptionEvents.Platform.Services do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SourceWriter.EventDispatch.SubscriptionEvents.Platform.Services.{DeviceEvents, Dictation, Unobstructed}

  @spec body() :: Types.c_source()
  def body do
    [DeviceEvents.body(), Dictation.body(), Unobstructed.body()]
    |> IO.iodata_to_binary()
  end
end
