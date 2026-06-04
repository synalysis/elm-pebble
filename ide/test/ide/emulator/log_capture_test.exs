defmodule Ide.Emulator.LogCaptureTest do
  use ExUnit.Case, async: true

  alias Ide.Emulator.LogCapture
  alias Ide.Emulator.PebbleProtocol.LogLines

  test "snapshot reports fault from protocol lines" do
    snapshot =
      LogCapture.snapshot(
        %{console_port: nil, protocol_router_pid: nil},
        duration_ms: 1
      )

    assert snapshot.source == "embedded"
    refute snapshot.fault_detected
  end

  test "LogLines detects app fault strings" do
    assert LogLines.fault_line?("App fault! {uuid} PC: 0 LR: 0")
  end
end
