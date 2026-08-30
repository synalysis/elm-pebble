defmodule Elmc.WasmUnionRecordTagTest do
  use ExUnit.Case, async: false

  alias Elmc.Test.WasmRcTrackHarness

  @runner Path.expand("support/wasm_union_record_tag_probe.mjs", __DIR__)

  @tag :wasm_execute
  test "union_tag_as_int and tuple_proj accept 2-field record unions" do
    if WasmRcTrackHarness.execution_tools_available?() do
      case WasmRcTrackHarness.run_node_script(@runner, []) do
        {:ok, output} ->
          assert output =~ "[union-record-tag] ok"

        {:error, output} ->
          flunk("union record-tag probe failed:\n#{output}")
      end
    end
  end
end
