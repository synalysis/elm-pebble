defmodule Elmc.WasmWebMultiRouteBytesTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Wasm.ProjectWriter
  alias Elmc.Test.WasmRcTrackHarness

  @tag :wasm_execute
  @tag :wasm_elm_pages_corpus
  test "multi-route pageDataFromJs bytes deliver on navigation" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_multi_route_bytes_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_multi_route_bytes", __DIR__)
        File.rm_rf!(out_dir)

        assert {:ok, _} =
                 Elmc.compile(root, %{
                   out_dir: out_dir,
                   targets: [:wasm],
                   web: true,
                   entry_module: "Main",
                   strip_dead_code: true,
                   wasm_strict: true
                 })

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_probe(out_dir) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "multi_route_bytes_ok"

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("multi route bytes probe failed:\n#{output}")
            end
        end
    end
  end

  @runner Path.expand("support/wasm_multi_route_bytes_probe_runner.mjs", __DIR__)

  defp run_probe(out_dir), do: WasmRcTrackHarness.run_node_script(@runner, [out_dir])

  defp execution_tools_available? do
    System.find_executable("node") != nil and
      (System.find_executable("wat2wasm") != nil or System.find_executable("npx") != nil)
  end
end
