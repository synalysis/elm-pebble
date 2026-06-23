defmodule Ide.Debugger.GeolocationResponsesTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.GeolocationResponses
  alias Ide.Debugger.RuntimeSurfaces

  test "apply_after_step skips geolocation sources" do
    state = RuntimeSurfaces.default_watch()
    ctx = %{}

    assert GeolocationResponses.apply_after_step(state, :watch, "Tick", %{}, "geolocation", ctx) ==
             state
  end

  test "update_branch_requests_command? is false without introspect cmd calls" do
    refute GeolocationResponses.update_branch_requests_command?(%{}, "Tick")
  end

  test "apply_after_step skips when runtime followups already include geolocation bridge" do
    state = %{watch: %{}}
    events = :ets.new(:geo_events, [:set, :private])

    ctx = %{
      introspect_for: fn _state, _target ->
        %{
          "subscription_calls" => [
            %{
              "target" => "Pebble.Companion.Geolocation.onCurrentPosition",
              "callback_constructor" => "GotLocation"
            }
          ],
          "update_cmd_calls" => [
            %{
              "target" => "Pebble.Companion.Geolocation.getCurrentPosition",
              "name" => "getCurrentPosition",
              "branch_constructor" => "Refresh"
            }
          ]
        }
      end,
      append_event: fn st, type, payload ->
        :ets.insert(events, {type, payload})
        st
      end,
      apply_step_once: fn st, _, _, _, _, _ -> st end,
      source_root_for_target: fn :watch -> "watch" end
    }

    followups = [
      %{
        "source" => "companion_bridge_command",
        "package" => "pebble/companion",
        "command" => %{"api" => "geolocation", "op" => "getCurrentPosition"}
      }
    ]

    assert GeolocationResponses.apply_after_step(
             state,
             :watch,
             "Refresh",
             %{},
             "provided",
             ctx,
             followups
           ) == state

    assert :ets.tab2list(events) == []
  end

  test "init_requested_for_surface? is true when runtime active subscriptions include geolocation" do
    state = %{
      watch: %{
        model: %{
          "active_subscriptions" => [
            %{
              "target" => "Pebble.Companion.Geolocation.onCurrentPosition",
              "message" => "GotLocation"
            }
          ]
        }
      }
    }

    assert Ide.Debugger.Geolocation.init_requested_for_surface?(state, :watch, %{})
  end
end
