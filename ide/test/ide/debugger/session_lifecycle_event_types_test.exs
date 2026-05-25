defmodule Ide.Debugger.SessionLifecycleEventTypesTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger

  test "start_session and reset append typed lifecycle payloads" do
    slug = "session_lifecycle_#{System.unique_integer([:positive])}"
    on_exit(fn -> Debugger.forget_project(slug) end)

    assert {:ok, state} =
             Debugger.start_session(slug, %{
               "watch_profile_id" => "basalt",
               "launch_reason" => "LaunchUser"
             })

    start_event = Enum.find(state.events, &(&1.type == "debugger.start"))
    assert start_event.payload.launch_reason == "LaunchUser"
    assert start_event.payload.watch_profile_id == "basalt"

    assert {:ok, reset_state} = Debugger.reset(slug)
    reset_event = Enum.find(reset_state.events, &(&1.type == "debugger.reset"))
    assert reset_event
    assert reset_event.payload == %{}
  end

  test "tick appends TickEventPayload contract fields" do
    slug = "tick_event_#{System.unique_integer([:positive])}"
    on_exit(fn -> Debugger.forget_project(slug) end)

    assert {:ok, _} = Debugger.start_session(slug)
    assert {:ok, state} = Debugger.tick(slug, %{"target" => "watch", "count" => 2})

    tick_event = Enum.find(state.events, &(&1.type == "debugger.tick"))
    assert tick_event.payload.count == 2
    assert tick_event.payload.target == "watch"
    assert "watch" in tick_event.payload.targets
  end
end
