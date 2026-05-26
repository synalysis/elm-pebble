defmodule Ide.Debugger.ConfigurationSaveTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.ConfigurationSave

  test "closed_bridge_event encodes values as JSON response" do
    event = ConfigurationSave.closed_bridge_event(%{"theme" => "dark"})

    assert event["event"] == "configuration.closed"
    assert Jason.decode!(event["payload"]["response"]) == %{"theme" => "dark"}
  end

  test "message_payload falls back to FromBridge without subscription callback" do
    {message, value} =
      ConfigurationSave.message_payload(%{}, %{}, %{"event" => "configuration.closed"}, %{})

    assert message == "FromBridge"
    assert value == %{"ctor" => "FromBridge", "args" => [%{"event" => "configuration.closed"}]}
  end
end
