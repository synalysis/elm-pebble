defmodule Ide.Debugger.ConfigurationSaveTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.ConfigurationSave

  test "closed_bridge_event encodes values as JSON response" do
    event = ConfigurationSave.closed_bridge_event(%{"theme" => "dark"})

    assert event["event"] == "configuration.closed"
    assert Jason.decode!(event["payload"]["response"]) == %{"theme" => "dark"}
  end

  test "message_payload falls back to FromBridge without subscription callback" do
    bridge_event = %{
      "event" => "configuration.closed",
      "payload" => %{"response" => ~s({"theme":"dark"})}
    }

    {message, value} = ConfigurationSave.message_payload(%{}, %{}, bridge_event, %{})

    assert message == "FromBridge"
    assert value == %{"ctor" => "FromBridge", "args" => [bridge_event]}
  end

  test "message_payload uses configuration.closed bridge event when subscription callback is present" do
    bridge_event = %{
      "event" => "configuration.closed",
      "payload" => %{"response" => ~s({"backgroundColor":"blue"})}
    }

    introspect = %{
      "subscription_calls" => [
        %{
          "callback_constructor" => "FromBridge",
          "target" => "GeneratedPreferences.onConfiguration"
        }
      ]
    }

    bridge_ctx = %{
      introspect: fn
        _state, :companion -> introspect
        _state, :phone -> %{}
      end,
      cmd_calls: &Ide.Debugger.IntrospectAccess.cmd_calls/2
    }

    {message, value} =
      ConfigurationSave.message_payload(%{companion: %{model: %{}}}, %{}, bridge_event, bridge_ctx)

    assert message == "FromBridge"
    assert value == %{"ctor" => "FromBridge", "args" => [bridge_event]}
  end
end
