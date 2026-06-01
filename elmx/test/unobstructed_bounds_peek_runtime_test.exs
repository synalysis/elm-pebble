defmodule Elmx.UnobstructedBoundsPeekRuntimeTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.{Followups, MessageDecode, Pebble, Pebble.SpecialValues}

  test "Pebble.UnobstructedArea.currentBounds rewrites to unobstructed peek runtime call" do
    callback = %{"ctor" => "GotBounds", "args" => []}

    assert {:ok, %{op: :runtime_call, function: "elmx_unobstructed_current_bounds", args: [^callback]}} =
             SpecialValues.rewrite("Pebble.UnobstructedArea.currentBounds", [callback])
  end

  test "unobstructed bounds peek emits device command with rect payload" do
    callback = %{"ctor" => "GotBounds", "args" => []}

    cmd = Pebble.runtime_dispatch("elmx_unobstructed_current_bounds", [callback])

    assert cmd["kind"] == "cmd.device.unobstructed_bounds_peek"
    assert cmd["message"] == "GotBounds"
    assert %{"ctor" => "GotBounds", "args" => [bounds]} = cmd["message_value"]
    assert bounds["x"] == 0
    assert bounds["y"] == 0
    assert bounds["w"] == 144
    assert bounds["h"] == 168

    assert [%{"source" => "device_command", "message" => "GotBounds"}] =
             Followups.from_commands(cmd)
  end

  test "GotBounds followup message_value decodes to rect record" do
    callback = %{"ctor" => "GotBounds", "args" => []}
    cmd = Pebble.runtime_dispatch("elmx_unobstructed_current_bounds", [callback])

    assert {:GotBounds, rect} = MessageDecode.decode(cmd["message"], cmd["message_value"])
    assert rect["x"] == 0
    assert rect["w"] == 144
  end
end
