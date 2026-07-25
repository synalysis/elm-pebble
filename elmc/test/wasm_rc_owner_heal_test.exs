defmodule Elmc.WasmRcOwnerHealTest do
  use ExUnit.Case, async: false

  alias Elmc.Test.WasmRcTrackHarness

  @runner Path.expand("support/wasm_rc_owner_heal_probe.mjs", __DIR__)

  @tag :wasm_execute
  test "host RC heals over-released list still owned by a live tuple" do
    if WasmRcTrackHarness.execution_tools_available?() do
      case WasmRcTrackHarness.run_node_script(@runner, []) do
        {:ok, output} ->
          assert output =~ "[rc-owner-heal] ok"

        {:error, output} ->
          flunk("rc owner-heal probe failed:\n#{output}")
      end
    end
  end
end
