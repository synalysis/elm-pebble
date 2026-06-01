defmodule Ide.Debugger.RuntimeEventContractTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.Types.{RuntimeEvent, RuntimeEventLog, RuntimeEventPayload}

  test "contract_complete? and every known event type resolves a payload module" do
    assert RuntimeEventPayload.contract_complete?()

    for {type, kind} <- RuntimeEventPayload.known_event_types() do
      assert RuntimeEventPayload.known_event_type?(type)
      assert RuntimeEventPayload.kind_for(type) == kind
      assert RuntimeEventPayload.payload_module_for_type(type) != nil
    end
  end

  test "RuntimeEvent.build wraps typed payload with surface snapshots" do
    event =
      RuntimeEvent.build(1, "debugger.start", %{launch_reason: "LaunchUser"}, %{
        watch: %{"model" => %{}},
        companion: %{},
        phone: %{}
      })

    assert event.seq == 1
    assert event.type == "debugger.start"
    assert event.payload.launch_reason == "LaunchUser"
    assert is_map(event.watch)
  end

  test "RuntimeEventLog maps kinds to wire types and payload modules" do
    assert RuntimeEventLog.event_type(:start) == "debugger.start"
    assert RuntimeEventLog.payload_module(:replay) == RuntimeEventPayload.payload_module_for(:replay)
    assert RuntimeEventLog.wire_type?("debugger.contract")
    assert RuntimeEventLog.wire_type?("debugger.elm_introspect")
    refute RuntimeEventLog.wire_type?("debugger.unknown")
  end
end
