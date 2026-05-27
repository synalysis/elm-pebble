defmodule Ide.Emulator.QemuControlTest do
  use ExUnit.Case, async: true

  alias Ide.Emulator.QemuControl

  test "encode_battery clamps percent and encodes charging flag" do
    assert %{protocol: 5, payload: <<100, 1>>} = QemuControl.encode_battery(150, true)
    assert %{protocol: 5, payload: <<0, 0>>} = QemuControl.encode_battery(-5, false)
  end

  test "encode_compass packs heading and valid flag" do
    assert %{protocol: 12, payload: <<1, 44, 1>>} = QemuControl.encode_compass(300, true)
    assert %{protocol: 12, payload: <<1, 104, 0>>} = QemuControl.encode_compass(400, false)
  end

  test "encode_accel uses signed int16 big-endian" do
    assert %{protocol: 11, payload: <<0, 100, 255, 220, 0, 50>>} =
             QemuControl.encode_accel(100, -36, 50)
  end

  test "commands_from_simulator_settings includes only present keys" do
    commands =
      QemuControl.commands_from_simulator_settings(%{
        "battery_percent" => 42,
        "charging" => true,
        "clock_24h" => false
      })

    protocols = Enum.map(commands, & &1.protocol)
    assert 5 in protocols
    assert 9 in protocols
    refute 3 in protocols
    refute 12 in protocols
  end

  test "commands_from_simulator_settings on second fixture includes compass and bluetooth" do
    commands =
      QemuControl.commands_from_simulator_settings(%{
        "connected" => true,
        "compass_heading_deg" => 90,
        "compass_valid" => true,
        "timeline_peek" => true
      })

    protocols = Enum.map(commands, & &1.protocol)
    assert protocols == [3, 10, 12]
  end

  test "validate_payload requires accel and compass payload sizes" do
    assert :ok = QemuControl.validate_payload(11, <<0, 1, 0, 2, 0, 3>>)
    assert {:error, :invalid_qemu_payload} = QemuControl.validate_payload(11, <<0, 1>>)

    assert :ok = QemuControl.validate_payload(12, <<0, 90, 1>>)
    assert {:error, :invalid_qemu_payload} = QemuControl.validate_payload(12, <<0>>)
  end

  test "external_cli_commands maps simulator settings for Pebble CLI" do
    commands = QemuControl.external_cli_commands(%{"battery_percent" => 77, "charging" => true})

    assert [%{"control" => "battery", "percent" => "77", "charging" => "true"} | _] = commands
    assert Enum.any?(commands, &(&1["control"] == "bluetooth"))
    assert Enum.any?(commands, &(&1["control"] == "time_format"))
    assert Enum.any?(commands, &(&1["control"] == "timeline_quick_view"))
  end

  test "supported_controls omits unimplemented set_time" do
    refute "set_time" in QemuControl.supported_controls()
  end
end
