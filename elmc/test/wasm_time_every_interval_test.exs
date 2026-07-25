defmodule Elmc.WasmTimeEveryIntervalTest do
  use ExUnit.Case, async: false

  alias Elmc.Test.WasmRcTrackHarness

  @runner Path.expand("support/wasm_time_every_interval_probe.mjs", __DIR__)

  @tag :wasm_execute
  test "Time.every Float ms must not be read as handle id" do
    if WasmRcTrackHarness.execution_tools_available?() do
      case WasmRcTrackHarness.run_node_script(@runner, []) do
        {:ok, output} ->
          assert output =~ "[time-every-interval] ok"

        {:error, output} ->
          flunk("time.every interval probe failed:\n#{output}")
      end
    end
  end
end
