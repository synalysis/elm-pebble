defmodule Ide.Debugger.AgentHostsTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.AgentHosts

  defp hosts do
    AgentHosts.build(
      history_limit: 50,
      default_auto_fire_interval_ms: 1_000,
      append_event: fn state, _type, _payload -> state end,
      append_debugger_event: fn state, _type, _target, _message, _source -> state end,
      update: fn _slug, updater -> {:ok, updater.(%{running: true})} end,
      ensure_phone_state: & &1,
      human_slug_from_session_key: fn key -> key end
    )
  end

  test "tick_ingress host maps surface targets without capture-on-map bug" do
    host = hosts().tick_ingress
    assert is_function(host.apply_step_once, 6)
    assert is_function(host.tick_message_for_surface, 2)

    roots = [:watch] |> Enum.map(fn target -> host.source_root_for_target.(target) end)
    assert roots == ["watch"]
  end

  test "trigger_discovery host resolves lazy trigger_surface context" do
    host = hosts().trigger_discovery
    ctx = Ide.Debugger.TriggerDiscovery.resolve_trigger_surface(host)
    assert is_map(ctx)
    assert is_function(ctx.introspect_for, 2)
  end

  test "operation_deps normalize_target matches SurfaceTargets" do
    deps = hosts().operation_deps
    assert deps.normalize_target.("companion") == :companion
    assert deps.normalize_target.("phone") == :companion
  end

  test "append_event on hosts is a 3-arity function" do
    host = hosts()
    assert is_function(host.append_event, 3)
    assert host.append_event.(%{seq: 0}, "debugger.tick", %{"count" => 1}) == %{seq: 0}
  end
end
