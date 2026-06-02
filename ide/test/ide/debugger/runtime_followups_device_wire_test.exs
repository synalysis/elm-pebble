defmodule Ide.Debugger.RuntimeFollowupsDeviceWireTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.DeviceData

  test "DeviceData.finalize_request applies MinuteChanged payload to current_date_time preview" do
    model = %{
      "runtime_model" => %{},
      "simulated_date" => "2026-06-01",
      "simulated_time" => "15:44:00",
      "use_simulated_time" => true,
      "timezone_offset_min" => 120
    }

    req =
      %{kind: "current_date_time", response_message: "CurrentDateTime"}
      |> DeviceData.finalize_request(model, "MinuteChanged 46")

    assert req.preview["minute"] == 46
  end

  test "response_wire_for_callback builds CurrentDateTime wire without parent-message device row" do
    ei = %{
      "init_cmd_calls" => [
        %{
          "name" => "getCurrentDateTime",
          "target" => "PebbleCmd.getCurrentDateTime",
          "callback_constructor" => "CurrentDateTime"
        }
      ]
    }

    model = %{
      "runtime_model" => %{},
      "simulated_date" => "2026-06-01",
      "simulated_time" => "22:05:10",
      "use_simulated_time" => true,
      "timezone_offset_min" => 120
    }

    wire = DeviceData.response_wire_for_callback(ei, model, "CurrentDateTime", "MinuteChanged 6")

    assert %{"ctor" => "CurrentDateTime", "args" => [payload]} = wire
    assert payload["minute"] == 6
  end
end
