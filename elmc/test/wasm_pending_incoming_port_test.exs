defmodule Elmc.WasmPendingIncomingPortTest do
  use ExUnit.Case, async: false

  alias Elmc.Test.WasmRcTrackHarness

  @runner Path.expand("support/wasm_pending_incoming_port_probe.mjs", __DIR__)

  @tag :wasm_execute
  test "incoming port without a subscriber queues instead of returning unimplemented" do
    if WasmRcTrackHarness.execution_tools_available?() do
      case WasmRcTrackHarness.run_node_script(@runner, []) do
        {:ok, output} ->
          assert output =~ "[pending-port] ok"

        {:error, output} ->
          flunk("pending incoming port probe failed:\n#{output}")
      end
    end
  end
end
