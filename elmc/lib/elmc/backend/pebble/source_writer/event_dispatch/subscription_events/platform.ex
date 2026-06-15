defmodule Elmc.Backend.Pebble.SourceWriter.EventDispatch.SubscriptionEvents.Platform do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SourceWriter.EventDispatch.SubscriptionEvents.Platform.{Clock, Services}

  @spec body() :: Types.c_source()
  def body do
    [Services.body(), Clock.body()]
    |> IO.iodata_to_binary()
  end
end
