defmodule Elmc.Backend.Pebble.SourceWriter.EventDispatch.SubscriptionEvents do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SourceWriter.EventDispatch.SubscriptionEvents.{Input, Motion, Platform}

  @spec body() :: Types.c_source()
  def body do
    [Input.body(), Motion.body(), Platform.body()]
    |> IO.iodata_to_binary()
  end
end
