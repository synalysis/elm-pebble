defmodule Elmc.WasmArrayFoldrTest do
  use ExUnit.Case, async: false

  alias Elmc.Test.WasmRcTrackHarness

  @runner Path.expand("support/wasm_array_foldr_probe.mjs", __DIR__)

  @tag :wasm_execute
  test "host Array.foldr keeps ownership of list accumulators" do
    if WasmRcTrackHarness.execution_tools_available?() do
      case WasmRcTrackHarness.run_node_script(@runner, []) do
        {:ok, output} ->
          assert output =~ "[array-foldr] ok"

        {:error, output} ->
          flunk("array_foldr probe failed:\n#{output}")
      end
    end
  end
end
