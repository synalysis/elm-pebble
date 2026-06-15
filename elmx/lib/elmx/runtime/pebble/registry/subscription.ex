defmodule Elmx.Runtime.Pebble.Registry.Subscription do
  @moduledoc false

  alias Elmx.Runtime.Handler
  alias Elmx.Runtime.Pebble.Dispatch

  @type handler :: Handler.t()

  @spec handlers() :: %{String.t() => handler()}
  def handlers do
    for {suffix, target} <- [
          {"events_on_minute_change", "Pebble.Events.onMinuteChange"},
          {"button_on", "Pebble.Button.on"},
          {"accel_on_tap", "Pebble.Accel.onTap"},
          {"events_on_second_change", "Pebble.Events.onSecondChange"},
          {"button_on_press", "Pebble.Button.onPress"},
          {"button_on_release", "Pebble.Button.onRelease"}
        ],
        into: %{} do
      {"elmx_#{suffix}", {Dispatch, :subscription_cmd, target: target}}
    end
  end
end
