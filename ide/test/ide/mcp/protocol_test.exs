defmodule Ide.Mcp.ProtocolTest do
  use ExUnit.Case, async: true

  alias Ide.Mcp.Protocol

  test "json_safe converts runtime terms that Jason cannot encode" do
    ref = make_ref()

    payload =
      Protocol.json_safe(%{
        auto_tick: %{worker_pid: self(), ref: ref},
        tuple: {:ok, self()},
        status: :running
      })

    assert payload["auto_tick"]["worker_pid"] == inspect(self())
    assert payload["auto_tick"]["ref"] == inspect(ref)
    assert payload["tuple"] == ["ok", inspect(self())]
    assert payload["status"] == "running"
    assert is_binary(Jason.encode!(payload))
  end
end
