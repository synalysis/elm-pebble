defmodule Ide.Debugger.DeviceRequestTypesTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.DeviceRequest
  test "from_cmd_call maps Pebble time and battery introspect rows" do
    time_call = %{
      "name" => "getCurrentTimeString",
      "callback_constructor" => "CurrentTime",
      "branch_constructor" => "Tick"
    }

    battery_call = %{
      "name" => "getBatteryLevel",
      "callback_constructor" => "BatteryLevel"
    }

    [time_req] = DeviceRequest.from_cmd_call(time_call)
    [battery_req] = DeviceRequest.from_cmd_call(battery_call)

    assert time_req.kind == "current_time_string"
    assert time_req.response_message == "CurrentTime"
    assert battery_req.kind == "battery_level"
    assert battery_req.response_message == "BatteryLevel"
  end

  test "from_cmd_call maps qualified PebbleCmd target when name is derived from target" do
    call = %{
      "target" => "PebbleCmd.getCurrentDateTime",
      "name" => "getCurrentDateTime",
      "callback_constructor" => "CurrentDateTime",
      "branch_constructor" => "MinuteChanged"
    }

    [req] = DeviceRequest.from_cmd_call(call)

    assert req.kind == "current_date_time"
    assert req.response_message == "CurrentDateTime"
  end

  test "from_cmd_call maps health metric cmd on Health target" do
    health_call = %{
      "name" => "value",
      "target" => "PebbleWatch.health",
      "callback_constructor" => "HealthSteps"
    }

    [req] = DeviceRequest.from_cmd_call(health_call)

    assert req.kind == "health_value"
    assert req.response_message == "HealthSteps"
  end
end
