defmodule Ide.Debugger.SessionLifecycleTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.SessionDefaults
  alias Ide.Debugger.SessionLifecycle

  test "launch_bundle_from_state preserves profile and launch reason" do
    state =
      SessionDefaults.default_state("user:demo")
      |> Map.put(:watch_profile_id, "basalt")
      |> Map.put(:launch_context, %{"launch_reason" => "LaunchUser"})

    bundle = SessionLifecycle.launch_bundle_from_state(state)

    assert bundle.watch_profile_id == "basalt"
    assert bundle.launch_reason == "LaunchUser"
    assert is_map(bundle.launch_context)
    assert is_map(bundle.simulator_settings)
  end

  test "start_session clears history and marks running" do
    state = SessionDefaults.default_state("user:demo")
    bundle = SessionLifecycle.launch_bundle("basalt", "LaunchUser", %{})

    started = SessionLifecycle.start_session(state, "user:demo", bundle)

    assert started.running
    assert started.events == []
    assert started.seq == 0
    assert is_map(started.watch)
  end
end
