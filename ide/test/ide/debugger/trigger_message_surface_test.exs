defmodule Ide.Debugger.TriggerMessageSurfaceTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.RuntimeSurfaces
  alias Ide.Debugger.TriggerMessageSurface

  test "resolve prefers non-empty runtime subscription message for trigger" do
    state = %{
      watch:
        RuntimeSurfaces.default_watch()
        |> Map.put(:model, %{
          "active_subscriptions" => [
            %{
              "target" => "Pebble.Events.onMinuteChange",
              "event_kind" => "minute_changed",
              "message" => ""
            },
            %{
              "target" => "Pebble.Events.onMinuteChange",
              "event_kind" => "minute_changed",
              "message" => "MinuteChanged"
            }
          ]
        })
    }

    ctx = %{
      introspect_for: fn _state, _target -> %{} end,
      attach_payload: fn _state, _target, message, _trigger -> message end
    }

    assert TriggerMessageSurface.resolve(state, :watch, "minute_changed", nil, ctx) ==
             "MinuteChanged"
  end
end
