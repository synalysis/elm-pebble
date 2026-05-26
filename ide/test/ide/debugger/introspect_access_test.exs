defmodule Ide.Debugger.IntrospectAccessTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.IntrospectAccess

  test "list returns trimmed unique string entries" do
    ei = %{
      "msg_constructors" => [" Tick ", "Tick", "", 42, "Other"]
    }

    assert IntrospectAccess.list(ei, "msg_constructors") == ["Tick", "Other"]
  end

  test "cmd_calls normalizes activation_guards on subscription rows" do
    ei = %{
      "subscription_calls" => [
        %{
          "name" => "watch",
          "target" => "Sub.on",
          "callback_constructor" => "GotTick",
          "activation_guards" => [%{"kind" => "field_truthy", "subject" => "model.enabled"}]
        }
      ]
    }

    assert [%{"name" => "watch", "activation_guards" => [guard]}] =
             IntrospectAccess.cmd_calls(ei, "subscription_calls")

    assert guard == %{"kind" => "field_truthy", "subject" => "model.enabled"}
  end
end
