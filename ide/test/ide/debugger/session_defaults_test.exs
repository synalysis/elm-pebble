defmodule Ide.Debugger.SessionDefaultsTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.SessionDefaults

  test "default_auto_tick shape" do
    tick = SessionDefaults.default_auto_tick()
    assert tick.enabled == false
    assert tick.target == "all"
    assert tick.worker_pid == nil
  end

  test "session_key_from_state prefers scope_key" do
    assert SessionDefaults.session_key_from_state(%{scope_key: "user:proj"}) == "user:proj"
    assert SessionDefaults.session_key_from_state(%{project_slug: "proj"}) == "proj"
    assert SessionDefaults.session_key_from_state(%{}) == nil
  end

  test "ensure_phone_state fills missing surfaces" do
    state = SessionDefaults.ensure_phone_state(%{watch_profile_id: "basalt"})

    assert is_map(state.phone)
    assert is_map(state.watch)
    assert is_map(state.auto_tick)
    assert is_list(state.debugger_timeline)
  end
end
