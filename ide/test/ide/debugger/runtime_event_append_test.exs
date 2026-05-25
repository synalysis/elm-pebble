defmodule Ide.Debugger.RuntimeEventAppendTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.Types.{RuntimeEventAppend, RuntimeEventLog, RuntimeEventPayload}

  test "wire_type resolves elmc sub-kinds and standard kinds" do
    assert RuntimeEventAppend.wire_type(:elmc_check) == "debugger.elmc_check"
    assert RuntimeEventAppend.wire_type(:elmc_compile) == "debugger.elmc_compile"
    assert RuntimeEventAppend.wire_type(:start) == "debugger.start"
    assert RuntimeEventAppend.wire_type(:replay) == "debugger.replay"
  end

  test "known_wire_type? covers contract and elmc wire strings" do
    for {type, _kind} <- RuntimeEventPayload.known_event_types() do
      assert RuntimeEventAppend.known_wire_type?(type)
    end

    assert RuntimeEventAppend.known_wire_type?("debugger.elmc_check")
  end

  test "RuntimeEventLog known_wire_types aligns with payload modules" do
    assert RuntimeEventPayload.contract_complete?()

    for {type, kind} <- RuntimeEventLog.known_wire_types() do
      assert RuntimeEventPayload.kind_for(type) == kind
      assert RuntimeEventPayload.payload_module_for(kind) != nil
    end
  end
end
