defmodule Elmx.CompassPeekRuntimeTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.{Followups, MessageDecode, Pebble, Pebble.SpecialValues}

  test "Pebble.Compass.current rewrites to compass peek runtime call" do
    callback = %{"ctor" => "GotHeading", "args" => []}

    assert {:ok, %{op: :runtime_call, function: "elmx_compass_peek", args: [^callback]}} =
             SpecialValues.rewrite("Pebble.Compass.current", [callback])
  end

  test "compass peek emits device command with GotHeading Ok payload" do
    callback = %{"ctor" => "GotHeading", "args" => []}

    cmd = Pebble.runtime_dispatch("elmx_compass_peek", [callback])

    assert cmd["kind"] == "cmd.device.compass_peek"
    assert cmd["message"] == "GotHeading"
    assert %{"ctor" => "GotHeading", "args" => [result]} = cmd["message_value"]
    assert %{"ctor" => "Ok", "args" => [heading]} = result
    assert heading["degrees"] == 180.0
    assert heading["isValid"] == true

    assert [%{"source" => "device_command", "message" => "GotHeading"}] =
             Followups.from_commands(cmd)
  end

  test "GotHeading followup message_value decodes to Ok heading" do
    callback = %{"ctor" => "GotHeading", "args" => []}
    cmd = Pebble.runtime_dispatch("elmx_compass_peek", [callback])

    assert {:GotHeading, {:Ok, heading}} =
             MessageDecode.decode(cmd["message"], cmd["message_value"])

    assert heading["degrees"] == 180.0
    assert heading["isValid"] == true
  end

  test "compass peek resolves curried GotHeading callback from partial constructor" do
    callback = fn result -> {:GotHeading, result} end

    cmd = Pebble.runtime_dispatch("elmx_compass_peek", [callback])

    assert cmd["message"] == "GotHeading"
    assert %{"ctor" => "GotHeading", "args" => [result]} = cmd["message_value"]
    assert %{"ctor" => "Ok", "args" => [heading]} = result
    assert heading["degrees"] == 180.0
    assert heading["isValid"] == true

    assert [%{"source" => "device_command", "message" => "GotHeading"}] =
             Followups.from_commands(cmd)
  end
end
