defmodule Ide.Debugger.RuntimeEventKindTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.Types.{
    DeviceDataEventPayload,
    HotReloadEventPayload,
    MessageInEventPayload,
    PackageCmdEventPayload,
    PackageCmdErrorEventPayload,
    ProtocolTxRxPayload,
    ReplayEventPayload,
    RuntimeEventPayload,
    RuntimeExecEventPayload,
    RuntimeStatusEventPayload,
    StartEventPayload,
    ViewRenderEventPayload
  }

  test "kind_for maps debugger event type strings without parsing payload content" do
    assert RuntimeEventPayload.kind_for("debugger.update_in") == :update_in
    assert RuntimeEventPayload.kind_for("debugger.runtime_exec") == :runtime_exec
    assert RuntimeEventPayload.kind_for("debugger.unknown_event") == :generic
  end

  test "payload_module_for returns contract modules for typed kinds" do
    assert RuntimeEventPayload.payload_module_for(:update_in) == MessageInEventPayload
    assert RuntimeEventPayload.payload_module_for(:runtime_exec) == RuntimeExecEventPayload
    assert RuntimeEventPayload.payload_module_for(:hot_reload) == HotReloadEventPayload
    assert RuntimeEventPayload.payload_module_for(:package_cmd_error) == PackageCmdErrorEventPayload
    assert RuntimeEventPayload.payload_module_for(:protocol_tx_rx) == ProtocolTxRxPayload
    assert RuntimeEventPayload.payload_module_for(:runtime_status) == RuntimeStatusEventPayload
    assert RuntimeEventPayload.payload_module_for(:package_cmd) == PackageCmdEventPayload
    assert RuntimeEventPayload.payload_module_for(:start) == StartEventPayload
    assert RuntimeEventPayload.payload_module_for(:view_render) == ViewRenderEventPayload
    assert RuntimeEventPayload.payload_module_for(:device_data) == DeviceDataEventPayload
    assert RuntimeEventPayload.payload_module_for(:replay) == ReplayEventPayload
    assert RuntimeEventPayload.payload_module_for(:elmc) == Ide.Debugger.Types.ElmcEventPayload
    assert RuntimeEventPayload.payload_module_for(:elm_introspect) ==
             Ide.Debugger.Types.ElmIntrospectEventPayload
    assert RuntimeEventPayload.payload_module_for(:generic) == nil
  end

  test "ProtocolTxRxPayload.tx_rx_events returns paired tx/rx payloads" do
    events = ProtocolTxRxPayload.tx_rx_events("watch", "companion", "Ping", "init_cmd", nil)
    assert length(events) == 2
    assert Enum.all?(events, &(&1.payload.message == "Ping"))
  end

  test "ReplayEventPayload drift_band matches replay telemetry contract" do
    assert ReplayEventPayload.drift_band(nil) == "none"
    assert ReplayEventPayload.drift_band(3) == "mild"
    assert ReplayEventPayload.drift_band(11) == "high"
  end

  test "known_event_type? reflects declared contract event types" do
    assert RuntimeEventPayload.known_event_type?("debugger.init_in")
    assert RuntimeEventPayload.known_event_type?("debugger.package_cmd_error")
    refute RuntimeEventPayload.known_event_type?("debugger.not_a_real_type")
    assert RuntimeEventPayload.contract_complete?()
    assert RuntimeEventPayload.payload_module_for_type("debugger.watch_profile_set") !=
             nil
  end

  test "ProtocolTxRxPayload.from_reload matches reload source roots" do
    assert ProtocolTxRxPayload.from_reload("rev1", "phone").message == "PhoneReloaded:rev1"
    assert ProtocolTxRxPayload.from_reload("rev1", "protocol").message == "ProtocolReloaded:rev1"
    assert ProtocolTxRxPayload.from_reload("rev1", "watch").message == "Reloaded:rev1"
  end
end
