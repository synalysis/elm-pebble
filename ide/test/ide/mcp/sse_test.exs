defmodule Ide.Mcp.SseTest do
  use ExUnit.Case, async: true

  alias Ide.Mcp.Sse

  test "priming event uses an empty SSE data field" do
    assert Sse.priming_event() == "id: 0\ndata:\n\n"
    refute Sse.priming_event() =~ "data: {}"
  end

  test "message event wraps JSON-RPC payloads" do
    payload = %{"jsonrpc" => "2.0", "id" => 1, "result" => %{}}

    assert Sse.message_event(payload) ==
             "event: message\ndata: #{Jason.encode!(payload)}\n\n"
  end
end
