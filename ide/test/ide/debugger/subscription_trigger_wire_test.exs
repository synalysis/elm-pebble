defmodule Ide.Debugger.SubscriptionTriggerWireTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.SubscriptionTriggerWire

  test "opaque_gateway_trigger? detects phone/watch gateway triggers" do
    assert SubscriptionTriggerWire.opaque_gateway_trigger?("phone_to_watch")
    assert SubscriptionTriggerWire.opaque_gateway_trigger?("onWatchToPhone")
    refute SubscriptionTriggerWire.opaque_gateway_trigger?("on_hour_change")
  end

  test "message_value wraps bare payloads with constructor from message label" do
    assert SubscriptionTriggerWire.message_value("Tick", %{"n" => 1}) == %{
             "ctor" => "Tick",
             "args" => [%{"n" => 1}]
           }
  end

  test "constructor_message trims constructor labels" do
    assert SubscriptionTriggerWire.constructor_message("  HourChanged  ") == "HourChanged"
    assert SubscriptionTriggerWire.constructor_message("   ") == nil
  end
end
