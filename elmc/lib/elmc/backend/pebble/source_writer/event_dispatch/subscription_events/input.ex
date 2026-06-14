defmodule Elmc.Backend.Pebble.SourceWriter.EventDispatch.SubscriptionEvents.Input do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.EventDispatch.SubscriptionEvents.Input.{
    AccelData,
    AccelTap,
    Button,
    ButtonEvent,
    ButtonRaw
  }

  @spec body() :: Types.c_source()
  def body do
    [
      ButtonEvent.body(),
      Button.body(),
      ButtonRaw.body(),
      AccelTap.body(),
      AccelData.body()
    ]
    |> IO.iodata_to_binary()
  end
end
