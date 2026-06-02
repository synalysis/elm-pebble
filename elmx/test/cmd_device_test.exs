defmodule Elmx.CmdDeviceTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.{Cmd, Followups, MessageDecode, Pebble}

  test "device command puts stub payload in message_value args for nullary callback" do
    cmd = Cmd.device("clock_style_24h", :ClockStyle24h, true)

    assert cmd["message"] == "ClockStyle24h"
    assert cmd["message_value"] == %{"ctor" => "ClockStyle24h", "args" => [true]}
    assert cmd["value"] == true
  end

  test "device command preserves callback args when already present" do
    callback = {:GotHeading, {:Ok, %{"degrees" => 90.0, "isValid" => true}}}
    cmd = Cmd.device("compass_peek", callback, {:Ok, %{}})

    assert length(cmd["message_value"]["args"]) == 1
    assert get_in(cmd["message_value"], ["ctor"]) == "GotHeading"
  end

  test "storage read_int command wires default into message_value args" do
    cmd = Cmd.storage_read_int(42, :PlayerSettingLoaded, 3)

    assert cmd["message"] == "PlayerSettingLoaded"
    assert cmd["message_value"] == %{"ctor" => "PlayerSettingLoaded", "args" => [3]}
  end

  test "followup row decodes device clock and battery messages" do
    cmd =
      Pebble.runtime_dispatch("elmx_time_clock_style_24h", [:ClockStyle24h])
      |> Cmd.normalize()

    [followup] = Followups.from_commands([cmd])

    assert MessageDecode.decode(followup["message"], followup["message_value"]) ==
             {:ClockStyle24h, true}

    battery =
      Pebble.runtime_dispatch("elmx_system_battery_level", [:BatteryLevelChanged])
      |> Cmd.normalize()

    [battery_followup] = Followups.from_commands([battery])

    assert MessageDecode.decode(battery_followup["message"], battery_followup["message_value"]) ==
             {:BatteryLevelChanged, 88}
  end

  test "MessageDecode decodes timeline string with True suffix" do
    assert MessageDecode.decode("HealthSupported False") == {:HealthSupported, false}
    assert MessageDecode.decode("ClockStyle24h True") == {:ClockStyle24h, true}
  end
end
