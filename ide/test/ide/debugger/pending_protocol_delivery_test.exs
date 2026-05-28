defmodule Ide.Debugger.PendingProtocolDeliveryTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.PendingProtocolDelivery

  test "enqueue stores payload for async drain" do
  state = %{
    companion: %{}
  }

  payload = %{"from" => "watch", "to" => "companion", "message" => "Ping"}

  next = PendingProtocolDelivery.enqueue(state, :companion, payload)

  assert [%{"recipient" => "companion", "payload" => ^payload}] =
           PendingProtocolDelivery.pending(next)
  end
end
